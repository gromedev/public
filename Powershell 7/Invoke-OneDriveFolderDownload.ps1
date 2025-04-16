# -----------------------------------------------
# CONFIGURATION SECTION
# -----------------------------------------------
$Config = @{
    ClientId = ""
    TenantId = ""
    UserEmail = ""
    TargetFolder = "Public"
    LocalFolder = "C:\temp\Public"
    BatchSizeMB = 100  # Write to disk after 100 MB
    MaxParallelTasks = 10  # Concurrent API calls/downloads
    MemoryThresholdGB = 1.0  # Clear batch buffer if memory exceeds 1 GB
    RetryMaxAttempts = 3  # Max retries for API failures
    RetryBaseDelaySeconds = 2  # Base delay for exponential backoff
}

# -----------------------------------------------
# ENVIRONMENT CHECK
# -----------------------------------------------
Write-Host "Starting environment validation..."

# Verify PowerShell 7
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "[✗] This script requires PowerShell 7 or higher. Current version: $($PSVersionTable.PSVersion)"
    exit
}

# Check architecture
$arch = (Get-ComputerInfo).WindowsProductName -match "ARM" ? "ARM64" : "x64"
if ($arch -eq "ARM64") {
    Write-Warning "[!] Running on ARM64. Ensure performance is adequate."
} else {
    Write-Host "[✓] System architecture: $arch"
}

# -----------------------------------------------
# Ensure MSAL.PS is installed
# -----------------------------------------------
if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
    Write-Host "[+] Installing MSAL.PS module..."
    Install-Module -Name MSAL.PS -Scope CurrentUser -Force -AllowClobber
} else {
    Write-Host "[✓] MSAL.PS module is already installed."
}

Import-Module MSAL.PS

# -----------------------------------------------
# Helper Functions
# -----------------------------------------------
function Get-CurrentMemoryUsage {
    try {
        $process = Get-Process -Id $pid
        return $process.WorkingSet64 / 1GB
    } catch {
        Write-Warning "Failed to get memory usage: $_"
        return 0
    }
}

function Invoke-RetryableOperation {
    param (
        [string]$Operation,
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = $Config.RetryMaxAttempts,
        [int]$BaseDelaySeconds = $Config.RetryBaseDelaySeconds
    )
    
    $attempt = 1
    while ($attempt -le $MaxRetries) {
        try {
            return & $ScriptBlock
        } catch {
            if ($_.Exception.Response.StatusCode -eq 429) {
                $retryAfter = $_.Exception.Response.Headers["Retry-After"] ?? $BaseDelaySeconds
                Write-Warning "$Operation hit rate limit (Attempt $attempt of $MaxRetries). Waiting $retryAfter seconds..."
                Start-Sleep -Seconds $retryAfter
            } elseif ($attempt -lt $MaxRetries) {
                $delay = $BaseDelaySeconds * [math]::Pow(2, ($attempt - 1))
                Write-Warning "$Operation failed (Attempt $attempt of $MaxRetries). Waiting $delay seconds..."
                Start-Sleep -Seconds $delay
            } else {
                Write-Error "Failed to execute $Operation after $MaxRetries attempts: $_"
                throw
            }
            $attempt++
        }
    }
}

function Write-BatchToDisk {
    param (
        [System.Collections.Concurrent.ConcurrentBag[hashtable]]$Batch
    )
    
    if (-not $script:Mutex) { $script:Mutex = New-Object System.Threading.Mutex }
    
    try {
        $script:Mutex.WaitOne() | Out-Null
        foreach ($item in $Batch) {
            $localPath = $item.LocalPath
            $content = $item.Content
            $directory = Split-Path $localPath -Parent
            if (-not (Test-Path $directory)) {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
            }
            [System.IO.File]::WriteAllBytes($localPath, $content)
            Write-Verbose "[✓] Downloaded '$($item.FileName)'"
        }
    } catch {
        Write-Warning "Failed to write batch: $_"
    } finally {
        $script:Mutex.ReleaseMutex()
    }
}

function Invoke-ScriptCleanup {
    if ($script:Mutex) {
        $script:Mutex.Dispose()
        $script:Mutex = $null
    }
    if ($script:HttpClient) {
        $script:HttpClient.Dispose()
        $script:HttpClient = $null
    }
    [System.GC]::Collect()
}

# -----------------------------------------------
# Authenticate using System Browser
# -----------------------------------------------
Write-Host "`n[🔐] Authenticating with Microsoft Graph using system browser..."

try {
    $Scopes = "Files.Read.All", "offline_access"
    $tokenResponse = Get-MsalToken -ClientId $Config.ClientId `
                                    -TenantId $Config.TenantId `
                                    -Scopes $Scopes `
                                    -Interactive `
                                    -RedirectUri "http://localhost" `
                                    -UseEmbeddedWebView:$false

    if (-not $tokenResponse.AccessToken) {
        throw "Authentication returned null token."
    }
    $AccessToken = $tokenResponse.AccessToken
    $Headers = @{ Authorization = "Bearer $AccessToken" }
    Write-Host "[✓] Authentication successful."
} catch {
    Write-Error "[✗] Authentication failed: $_"
    exit
}

# -----------------------------------------------
# Find Folder
# -----------------------------------------------
Write-Host "`n[📁] Locating OneDrive folder '$($Config.TargetFolder)'..."

$folderUrl = "https://graph.microsoft.com/v1.0/me/drive/root:/$($Config.TargetFolder)`?select=id"
try {
    $folder = Invoke-RetryableOperation -Operation "Find folder" -ScriptBlock {
        Invoke-RestMethod -Headers $Headers -Uri $folderUrl -Method GET
    }
    if (-not $folder.id) {
        throw "Folder not found or no ID returned."
    }
    $folderId = $folder.id
    Write-Host "[✓] Found folder ID: $folderId"
} catch {
    Write-Error "[✗] Could not retrieve folder '$($Config.TargetFolder)'. $_"
    exit
}

# -----------------------------------------------
# Global Variables for Progress Tracking
# -----------------------------------------------
$script:TotalSizeGB = 0.0
$script:DownloadedSizeGB = 0.0
$script:FoldersProcessed = 0
$script:FileMetadata = @{}
$script:BatchBuffer = [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()
$script:BatchBufferSizeMB = 0
$script:LastProgressUpdateGB = 0.0
$script:HttpClient = $null
$script:Mutex = $null

# -----------------------------------------------
# Count Total Files and Size Recursively
# -----------------------------------------------
function Count-FilesRecursively {
    param (
        [string]$ParentFolderId,
        [string]$ParentFolderPath
    )
    
    $childrenUrl = "https://graph.microsoft.com/v1.0/me/drive/items/$ParentFolderId/children`?select=id,name,size,folder,@microsoft.graph.downloadUrl"
    try {
        $response = Invoke-RetryableOperation -Operation "Fetch folder contents" -ScriptBlock {
            Invoke-RestMethod -Headers $using:Headers -Uri $childrenUrl -Method GET
        }
        $items = $response.value
        
        [System.Threading.Interlocked]::Increment([ref]$script:FoldersProcessed)
        Write-Progress -Activity "Counting files in '$($using:Config.TargetFolder)'" `
                      -Status "Processed $script:FoldersProcessed folders" `
                      -Id 1

        $items | Where-Object { $_.folder } | ForEach-Object -Parallel {
            $item = $_
            $itemPath = if ($using:ParentFolderPath) { Join-Path $using:ParentFolderPath $item.name } else { $item.name }
            Import-Module MSAL.PS -ErrorAction SilentlyContinue
            & $using:Count-FilesRecursively -ParentFolderId $item.id -ParentFolderPath $itemPath
        } -ThrottleLimit $using:Config.MaxParallelTasks

        foreach ($item in ($items | Where-Object { -not $_.folder })) {
            $itemPath = if ($ParentFolderPath) { Join-Path $ParentFolderPath $item.name } else { $item.name }
            $script:FileMetadata[$item.id] = @{
                Path = $itemPath
                SizeGB = $item.size / 1GB
                DownloadUrl = $item."@microsoft.graph.downloadUrl"
            }
            $script:TotalSizeGB += $item.size / 1GB
        }
    } catch {
        Write-Warning "Error counting files in folder ID '$ParentFolderId': $_"
    }
}

# -----------------------------------------------
# Download Files with Streaming and Batching
# -----------------------------------------------
function Download-Files {
    param (
        [hashtable]$Files
    )
    
    $script:HttpClient = [System.Net.Http.HttpClient]::new()
    $script:HttpClient.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $AccessToken)

    $Files.GetEnumerator() | ForEach-Object -Parallel {
        $file = $_.Value
        $fileId = $_.Key
        $localPath = Join-Path $using:Config.LocalFolder $file.Path
        $fileName = Split-Path $localPath -Leaf
        $fileSizeGB = $file.SizeGB
        Import-Module MSAL.PS -ErrorAction SilentlyContinue

        try {
            $response = Invoke-RetryableOperation -Operation "Download file '$fileName'" -ScriptBlock {
                $response = $using:script:HttpClient.GetAsync($file.DownloadUrl).Result
                $response.EnsureSuccessStatusCode()
                return $response
            }
            $content = $response.Content.ReadAsByteArrayAsync().Result

            $memoryUsage = & $using:Get-CurrentMemoryUsage
            if ($memoryUsage -gt $using:Config.MemoryThresholdGB) {
                Write-Warning "Memory usage high ($([math]::Round($memoryUsage,2))GB). Clearing batch buffer..."
                Write-BatchToDisk -Batch $using:script:BatchBuffer
                $using:script:BatchBuffer = [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()
                $using:script:BatchBufferSizeMB = 0
                [System.GC]::Collect()
            }

            $using:script:BatchBuffer.Add(@{
                LocalPath = $localPath
                FileName = $fileName
                Content = $content
                SizeMB = $content.Length / 1MB
            })
            $using:script:BatchBufferSizeMB += $content.Length / 1MB
            $using:script:DownloadedSizeGB += $fileSizeGB

            if ($using:script:BatchBufferSizeMB -ge $using:Config.BatchSizeMB) {
                Write-BatchToDisk -Batch $using:script:BatchBuffer
                $using:script:BatchBuffer = [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()
                $using:script:BatchBufferSizeMB = 0
            }

            if ($using:script:DownloadedSizeGB - $using:script:LastProgressUpdateGB -ge 0.01) {
                $percentComplete = [math]::Min(($using:script:DownloadedSizeGB / $using:script:TotalSizeGB) * 100, 100)
                Write-Progress -Activity "Downloading files from '$($using:Config.TargetFolder)'" `
                              -Status ("{0:N2} of {1:N2} GB downloaded" -f $using:script:DownloadedSizeGB, $using:script:TotalSizeGB) `
                              -PercentComplete $percentComplete `
                              -Id 2
                $using:script:LastProgressUpdateGB = $using:script:DownloadedSizeGB
            }
        } catch {
            Write-Warning "[✗] Failed to download '$fileName': $_"
        }
    } -ThrottleLimit $Config.MaxParallelTasks
}

# -----------------------------------------------
# Main Execution
# -----------------------------------------------
try {
    # Count total files and size
    Write-Host "`n[📊] Counting total files in '$($Config.TargetFolder)'..."
    Count-FilesRecursively -ParentFolderId $folderId -ParentFolderPath $Config.TargetFolder
    Write-Progress -Activity "Counting files in '$($Config.TargetFolder)'" `
                  -Status "Counting complete" `
                  -Id 1 `
                  -Completed
    Write-Host "[✓] Total size to download: {0:N2} GB" -f $script:TotalSizeGB

    # Create local folder
    if (-not (Test-Path $Config.LocalFolder)) {
        Write-Host "[+] Creating local folder: $($Config.LocalFolder)"
        New-Item -Path $Config.LocalFolder -ItemType Directory -Force | Out-Null
    }

    # Download files
    Write-Host "`nStarting download of files from '$($Config.TargetFolder)'..."
    Download-Files -Files $script:FileMetadata

    # Write remaining buffered files
    if ($script:BatchBuffer.Count -gt 0) {
        Write-BatchToDisk -Batch $script:BatchBuffer
        $script:BatchBuffer = [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()
        $script:BatchBufferSizeMB = 0
    }

    # Complete progress bar
    Write-Progress -Activity "Downloading files from '$($Config.TargetFolder)'" `
                  -Status "Download complete." `
                  -PercentComplete 100 `
                  -Id 2 `
                  -Completed

    Write-Host "Download complete! Files saved to: $($Config.LocalFolder)"
} finally {
    Invoke-ScriptCleanup
}

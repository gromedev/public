# -----------------------------------------------
# CONFIGURATION SECTION
# -----------------------------------------------
$ClientId = ""
$TenantId = ""
$UserEmail = ""
$TargetFolder = "Public"
$LocalFolder = "C:\temp\Public"

# -----------------------------------------------
# ENVIRONMENT CHECK
# -----------------------------------------------
Write-Host "Starting environment validation..."

# Check execution policy
$executionPolicy = Get-ExecutionPolicy
if ($executionPolicy -ne "RemoteSigned" -and $executionPolicy -ne "Unrestricted") {
    Write-Host "[!] Execution policy is '$executionPolicy'. Changing to 'RemoteSigned'..."
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
}

# Check architecture
$arch = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
if ($arch -match "ARM64") {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        Write-Warning "[!] You're running ARM64 PowerShell. If this script hangs, try running it in x64 PowerShell from:"
        Write-Host "    C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`n"
    } else {
        Write-Host "[✓] You're running in x64 PowerShell on an ARM64 system."
    }
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
# Authenticate using System Browser (avoids WebView2 issues)
# -----------------------------------------------
Write-Host "`n[🔐] Authenticating with Microsoft Graph using system browser..."

try {
    $Scopes = "Files.Read.All", "offline_access"
    $tokenResponse = Get-MsalToken -ClientId $ClientId `
                                    -TenantId $TenantId `
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
Write-Host "`n[📁] Locating OneDrive folder '$TargetFolder'..."

$folderUrl = "https://graph.microsoft.com/v1.0/me/drive/root:/$TargetFolder"
try {
    $folder = Invoke-RestMethod -Headers $Headers -Uri $folderUrl -Method GET
    if (-not $folder.id) {
        throw "Folder not found or no ID returned."
    }
    $folderId = $folder.id
    Write-Host "[✓] Found folder ID: $folderId"
} catch {
    Write-Error "[✗] Could not retrieve folder '$TargetFolder'. $_"
    exit
}

# -----------------------------------------------
# Global Variables for Progress Tracking
# -----------------------------------------------
$script:TotalSizeGB = 0.0
$script:DownloadedSizeGB = 0.0
$script:FoldersProcessed = 0

# -----------------------------------------------
# Count Total Files and Size Recursively
# -----------------------------------------------
function Count-FilesRecursively {
    param (
        [string]$ParentFolderId,
        [string]$ParentFolderPath
    )
    
    $childrenUrl = "https://graph.microsoft.com/v1.0/me/drive/items/$ParentFolderId/children"
    try {
        $response = Invoke-RestMethod -Headers $Headers -Uri $childrenUrl -Method GET
        $items = $response.value
        
        # Update progress for folder processing
        $script:FoldersProcessed++
        Write-Progress -Activity "Counting files in '$TargetFolder'" `
                      -Status "Processed $script:FoldersProcessed folders" `
                      -Id 1

        foreach ($item in $items) {
            $itemPath = if ($ParentFolderPath) { Join-Path $ParentFolderPath $item.name } else { $item.name }
            
            if ($item.folder) {
                # Recursively count files in subfolder
                Count-FilesRecursively -ParentFolderId $item.id -ParentFolderPath $itemPath
            } else {
                # Add file size to total (convert bytes to GB)
                $fileSizeGB = $item.size / 1GB
                $script:TotalSizeGB += $fileSizeGB
            }
        }
    } catch {
        Write-Warning "Error counting files in folder ID '$ParentFolderId': $_"
    }
}

# -----------------------------------------------
# Recursive Download Files with Progress Bar
# -----------------------------------------------
function Download-FilesRecursively {
    param (
        [string]$ParentFolderId,
        [string]$ParentFolderName,
        [string]$LocalParentPath
    )
    
    $childrenUrl = "https://graph.microsoft.com/v1.0/me/drive/items/$ParentFolderId/children"
    try {
        $response = Invoke-RestMethod -Headers $Headers -Uri $childrenUrl -Method GET
        $items = $response.value

        if (-not $items) {
            Write-Warning "No items found in folder '$ParentFolderName'."
            return
        }

        foreach ($item in $items) {
            $itemName = $item.name
            $downloadUrl = $item."@microsoft.graph.downloadUrl"
            $localItemPath = Join-Path $LocalParentPath $itemName

            if ($item.folder) {
                # Create local subfolder if it doesn't exist
                if (-not (Test-Path $localItemPath)) {
                    New-Item -Path $localItemPath -ItemType Directory -Force | Out-Null
                }
                Write-Host "[~] Entering subfolder '$itemName'..."
                Download-FilesRecursively -ParentFolderId $item.id `
                                         -ParentFolderName $itemName `
                                         -LocalParentPath $localItemPath
            } else {
                # It's a file, so download it
                try {
                    Write-Host "[>] Downloading '$itemName'..."
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $localItemPath
                    Write-Host "[✓] Downloaded '$itemName'."

                    # Update progress based on file size
                    $fileSizeGB = $item.size / 1GB
                    $script:DownloadedSizeGB += $fileSizeGB
                    $percentComplete = [math]::Min(($script:DownloadedSizeGB / $script:TotalSizeGB) * 100, 100)
                    Write-Progress -Activity "Downloading files from '$TargetFolder'" `
                                  -Status ("{0:N2} of {1:N2} GB downloaded" -f $script:DownloadedSizeGB, $script:TotalSizeGB) `
                                  -PercentComplete $percentComplete `
                                  -Id 2
                } catch {
                    Write-Host "[✗] Failed to download '$itemName': $_"
                }
            }
        }
    } catch {
        Write-Warning "Error processing folder '$ParentFolderName': $_"
    }
}

# -----------------------------------------------
# Main Execution
# -----------------------------------------------
# Count total files and size before starting download
Write-Host "`n[📊] Counting total files in '$TargetFolder'..."
Count-FilesRecursively -ParentFolderId $folderId -ParentFolderPath $TargetFolder
Write-Progress -Activity "Counting files in '$TargetFolder'" `
              -Status "Counting complete" `
              -Id 1 `
              -Completed
Write-Host "[✓] Total size to download: {0:N2} GB" -f $script:TotalSizeGB

# Start downloading files from the target folder
if (-not (Test-Path $LocalFolder)) {
    Write-Host "[+] Creating local folder: $LocalFolder"
    New-Item -Path $LocalFolder -ItemType Directory -Force | Out-Null
}

Write-Host "`nStarting download of files from '$TargetFolder'..."
Download-FilesRecursively -ParentFolderId $folderId `
                         -ParentFolderName $TargetFolder `
                         -LocalParentPath $LocalFolder

# Complete the progress bar
Write-Progress -Activity "Downloading files from '$TargetFolder'" `
              -Status "Download complete." `
              -PercentComplete 100 `
              -Id 2 `
              -Completed

Write-Host "Download complete! Files saved to: $LocalFolder"

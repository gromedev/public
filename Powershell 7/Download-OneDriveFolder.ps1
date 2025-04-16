# Ensure PowerShell 7 or later
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7 or later."
    exit
}

# Configuration
$Config = @{
    ClientId        = "c7a7e3f0-bdb1-4e2f-a0fe-38f6ffaf69b9"  # Your Azure AD app Client ID
    TenantId        = "b9870f18-de8b-4057-a8be-eb040cd41ce9"  # Your Tenant ID
    UserEmail       = "thomas@grome.dev"                       # User’s email
    TargetFolder    = "Public"                                 # OneDrive folder to download
    LocalFolder     = "C:\temp\Public"                         # Local destination
    ThrottleLimit   = 3                                        # Parallel download limit
    MaxRetries      = 3                                        # Retry attempts for throttling
    RetryBaseDelay  = 2                                        # Base delay (seconds) for retries
    BatchDelay      = 1                                        # Delay (seconds) between folders
}

# Install MSAL.PS if not present
if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
    Write-Host "[+] Installing MSAL.PS module..."
    Install-Module -Name MSAL.PS -Scope CurrentUser -Force -AllowClobber
}
Import-Module MSAL.PS

# Authenticate with Microsoft Graph using interactive login
Write-Host "[🔐] Authenticating with Microsoft Graph..."
Write-Host "A browser window will open for you to sign in."
try {
    $Scopes = "Files.Read.All", "offline_access"
    $tokenResponse = Get-MsalToken -ClientId $Config.ClientId `
                                   -TenantId $Config.TenantId `
                                   -Scopes $Scopes `
                                   -Interactive `
                                   -RedirectUri "http://localhost" `
                                   -UseEmbeddedWebView:$false
    if (-not $tokenResponse.AccessToken) {
        throw "Failed to obtain access token."
    }
    $headers = @{ Authorization = "Bearer $($tokenResponse.AccessToken)" }
    Write-Host "[✓] Authentication successful."
} catch {
    Write-Error "[✗] Authentication failed: $_"
    exit
}

# Locate the target folder
Write-Host "[📁] Locating folder '$($Config.TargetFolder)'..."
try {
    $folderUrl = "https://graph.microsoft.com/v1.0/me/drive/root:/$($Config.TargetFolder)"
    $folder = Invoke-RestMethod -Headers $headers -Uri $folderUrl -Method Get
    if (-not $folder.id) {
        throw "Folder not found."
    }
    $folderId = $folder.id
    Write-Host "[✓] Found folder ID: $folderId"
} catch {
    Write-Error "[✗] Failed to locate folder '$($Config.TargetFolder)': $_"
    exit
}

# Function to download files recursively
function Download-Folder {
    param (
        [string]$FolderId,
        [string]$FolderName,
        [string]$LocalPath
    )

    $pageSize = 999
    $childrenUrl = "https://graph.microsoft.com/v1.0/me/drive/items/$FolderId/children?`$top=$pageSize"
    try {
        # Fetch all items with pagination
        $items = [System.Collections.Generic.List[object]]::new()
        $nextLink = $childrenUrl
        while ($nextLink) {
            try {
                $response = Invoke-RestMethod -Headers $headers -Uri $nextLink -Method Get
                $items.AddRange($response.value)
                $nextLink = $response.'@odata.nextLink'
            } catch {
                if ($_.Exception.Response.StatusCode -eq 429 -or $_.ErrorDetails.Message -match "throttled") {
                    $retryAfter = if ($_.ErrorDetails.Message -match '"retryAfterSeconds":(\d+)') { [int]$Matches[1] } else { 30 }
                    Write-Verbose "Throttling detected for folder '$FolderName'. Waiting $retryAfter seconds..."
                    Start-Sleep -Seconds $retryAfter
                    continue
                }
                Write-Warning "Error fetching items in folder '$FolderName': $_"
                return
            }
        }

        if (-not $items) {
            Write-Verbose "No items in folder '$FolderName'."
            return
        }

        # Separate files and folders
        $files = $items | Where-Object { -not $_.folder }
        $folders = $items | Where-Object { $_.folder }

        # Download files in parallel with retries
        if ($files) {
            $files | ForEach-Object -ThrottleLimit $Config.ThrottleLimit -Parallel {
                $file = $_
                if (-not $file -or -not $file.name) {
                    Write-Warning "Skipping invalid item (no name) in folder '$using:FolderName'."
                    return
                }
                $fileName = $file.name
                $localFilePath = Join-Path $using:LocalPath $fileName
                $downloadUrl = $null
                if ($file.PSObject.Properties.Name -contains '@microsoft.graph.downloadUrl' -and $null -ne $file.'@microsoft.graph.downloadUrl' -and $file.'@microsoft.graph.downloadUrl' -ne '') {
                    $downloadUrl = $file.'@microsoft.graph.downloadUrl'
                }
                if (-not $downloadUrl) {
                    Write-Warning "No download URL for '$fileName' in '$using:FolderName'. Skipping."
                    return
                }

                $attempt = 1
                $success = $false
                while (-not $success -and $attempt -le $using:Config.MaxRetries) {
                    try {
                        Write-Verbose "[>] Downloading '$fileName' (Attempt $attempt)..."
                        Invoke-WebRequest -Uri $downloadUrl -OutFile $localFilePath
                        Write-Verbose "[✓] Downloaded '$fileName'."
                        $success = $true
                    } catch {
                        if ($_.Exception.Response.StatusCode -eq 429 -or $_.ErrorDetails.Message -match "throttled") {
                            $retryAfter = if ($_.ErrorDetails.Message -match '"retryAfterSeconds":(\d+)') { [int]$Matches[1] } else { 30 }
                            Write-Verbose "Throttling detected for '$fileName'. Waiting $retryAfter seconds..."
                            Start-Sleep -Seconds $retryAfter
                        } else {
                            Write-Warning "Failed to download '$fileName' after $attempt attempts: $_"
                            break
                        }
                        $attempt++
                    }
                }
            }
        }

        # Process subfolders sequentially with batch delay
        foreach ($folder in $folders) {
            if (-not $folder -or -not $folder.name) {
                Write-Warning "Skipping invalid folder (no name) in '$FolderName'."
                continue
            }
            $subFolderName = $folder.name
            $subFolderPath = Join-Path $LocalPath $subFolderName
            New-Item -Path $subFolderPath -ItemType Directory -Force | Out-Null
            Write-Verbose "[~] Processing subfolder '$subFolderName'..."
            Download-Folder -FolderId $folder.id `
                            -FolderName $subFolderName `
                            -LocalPath $subFolderPath
            # Batch delay to pace requests
            Start-Sleep -Seconds $Config.BatchDelay
        }

        # Memory cleanup after folder
        [System.GC]::Collect()
    } catch {
        Write-Warning "Error processing folder '$FolderName': $_"
    }
}

# Main execution
if (-not (Test-Path $Config.LocalFolder)) {
    Write-Host "[+] Creating local folder: $($Config.LocalFolder)"
    New-Item -Path $Config.LocalFolder -ItemType Directory -Force | Out-Null
}

Write-Host "[✓] Starting download of '$($Config.TargetFolder)'..."
Download-Folder -FolderId $folderId `
                -FolderName $Config.TargetFolder `
                -LocalPath $Config.LocalFolder

Write-Host "[✓] Download complete. Files saved to: $($Config.LocalFolder)"

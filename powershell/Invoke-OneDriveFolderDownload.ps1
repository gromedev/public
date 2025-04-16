<#
Register an App in Azure AD with http://localhost as the Redirect URI.
Grant API Permissions (e.g., Files.Read.All, offline_access, as delegated)
Authenticate using MSAL.PS with http://localhost for the redirect.
Remove unwanted URIs (e.g., https://login.microsoftonline.com/common/oauth2/nativeclient).
Use the token for Microsoft Graph API access.
#>

# -----------------------------------------------
# CONFIGURATION SECTION
# -----------------------------------------------
$ClientId = ""
$TenantId = ""
$UserEmail = ""
$TargetFolder = "Documents"
$LocalFolder = "C:\temp\Documents"

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
Write-Host "Authenticating with Microsoft Graph using system browser..."

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
}

# -----------------------------------------------
# Recursive Download Files
# -----------------------------------------------
function Download-FilesRecursively {
    param (
        [string]$ParentFolderId,
        [string]$ParentFolderName
    )
    
    $childrenUrl = "https://graph.microsoft.com/v1.0/me/drive/items/$ParentFolderId/children"
    
    try {
        $response = Invoke-RestMethod -Headers $Headers -Uri $childrenUrl -Method GET
        if (-not $response.value) {
            Write-Warning "No files found in folder '$ParentFolderName'."
            return
        }

        foreach ($item in $response.value) {
            $fileName = $item.name
            $downloadUrl = $item."@microsoft.graph.downloadUrl"

            if ($item.folder) {
                Write-Host "[~] Entering subfolder '$fileName'..."
                Download-FilesRecursively -ParentFolderId $item.id -ParentFolderName $fileName
            } else {
                # It's a file, so download it
                $localPath = Join-Path $LocalFolder $fileName
                try {
                    Write-Host "[>] Downloading '$fileName'..."
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $localPath
                    Write-Host "[✓] Downloaded '$fileName'."
                } catch {
                    Write-Host "[✗] Failed to download '$fileName': $_"
                }
            }
        }
    } catch {
        Write-Error "[✗] Error while fetching files in folder '$ParentFolderName': $_"
    }
}

# Start downloading files from the target folder
if (-not (Test-Path $LocalFolder)) {
    Write-Host "[+] Creating local folder: $LocalFolder"
    New-Item -Path $LocalFolder -ItemType Directory -Force | Out-Null
}

Write-Host "Starting download of files from '$TargetFolder'..."
Download-FilesRecursively -ParentFolderId $folderId -ParentFolderName $TargetFolder

Write-Host "Download complete! Files saved to: $LocalFolder"

# Define configuration
$Config = @{
    ClientId = ""
    TenantId = ""
    UserEmail = ""
    TargetFolder = "Public"  # OneDrive folder to download
    LocalFolder  = "C:\temp\Public"  # Local destination
}

# -----------------------------------------------
# Ensure MSAL.PS is installed
# -----------------------------------------------
if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
    Write-Host "[+] Installing MSAL.PS module..."
    Install-Module -Name MSAL.PS -Scope CurrentUser -Force -AllowClobber
}

Import-Module MSAL.PS

# -----------------------------------------------
# Authenticate using System Browser
# -----------------------------------------------
Write-Host "[🔐] Authenticating with Microsoft Graph..."

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
Write-Host "[📁] Locating OneDrive folder '$($Config.TargetFolder)'..."

$folderUrl = "https://graph.microsoft.com/v1.0/me/drive/root:/$($Config.TargetFolder)"
try {
    $folder = Invoke-RestMethod -Headers $Headers -Uri $folderUrl -Method GET
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
# Recursive Download Files
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
# Start downloading files from the target folder
if (-not (Test-Path $Config.LocalFolder)) {
    Write-Host "[+] Creating local folder: $($Config.LocalFolder)"
    New-Item -Path $Config.LocalFolder -ItemType Directory -Force | Out-Null
}

Write-Host "`nStarting download of files from '$($Config.TargetFolder)'..."
Download-FilesRecursively -ParentFolderId $folderId `
                         -ParentFolderName $Config.TargetFolder `
                         -LocalParentPath $Config.LocalFolder

Write-Host "Download complete! Files saved to: $($Config.LocalFolder)"

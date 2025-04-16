# Ensure running in PowerShell 7 or later
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7 or later."
    exit
}

# Define configuration
$Config = @{
    ClientId     = ""
    TenantId     = ""
    UserEmail    = ""
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
        # Handle pagination to get all items
        $items = @()
        $nextLink = $childrenUrl
        while ($nextLink) {
            $response = Invoke-RestMethod -Headers $Headers -Uri $nextLink -Method GET
            $items += $response.value
            $nextLink = $response.'@odata.nextLink'
        }

        if (-not $items) {
            Write-Verbose "No items found in folder '$ParentFolderName'."
            return
        }

        # Process folders and files
        foreach ($item in $items) {
            $itemName = $item.name
            $localItemPath = Join-Path $LocalParentPath $itemName

            if ($item.folder) {
                # Create local subfolder if it doesn't exist
                if (-not (Test-Path $localItemPath)) {
                    New-Item -Path $localItemPath -ItemType Directory -Force | Out-Null
                }
                Write-Verbose "[~] Entering subfolder '$itemName'..."
                Download-FilesRecursively -ParentFolderId $item.id `
                                         -ParentFolderName $itemName `
                                         -LocalParentPath $localItemPath
            } else {
                # It's a file, queue the download with BITS
                $downloadUrl = $item."@microsoft.graph.downloadUrl"
                Write-Verbose "[>] Queueing download for '$itemName'..."
                try {
                    Start-BitsTransfer -Source $downloadUrl -Destination $localItemPath -DisplayName $itemName
                } catch {
                    Write-Warning "Failed to queue download for '$itemName': $_"
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

Write-Host "[✓] Starting download process..."
Download-FilesRecursively -ParentFolderId $folderId `
                         -ParentFolderName $Config.TargetFolder `
                         -LocalParentPath $Config.LocalFolder

Write-Host "[✓] All downloads have been queued. Waiting for transfers to complete..."

while ($true) {
    $transfers = Get-BitsTransfer | Where-Object { $_.JobState -in @('Transferring', 'Connecting', 'Queued') }
    if (-not $transfers) {
        break
    }
    $count = $transfers.Count
    Write-Host "[~] $count transfers still in progress..."
    Start-Sleep -Seconds 10
}

# Check for failed transfers
$failedTransfers = Get-BitsTransfer | Where-Object { $_.JobState -eq 'Error' }
if ($failedTransfers) {
    Write-Host "[✗] The following transfers failed:"
    $failedTransfers | ForEach-Object {
        Write-Host " - $($_.DisplayName): $($_.ErrorDescription)"
    }
} else {
    Write-Host "[✓] All transfers completed successfully."
}

# Clean up BITS transfers
Get-BitsTransfer | Remove-BitsTransfer

Write-Host "Download process finished."

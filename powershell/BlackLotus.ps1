<#
.AUTHOR 
  thomas@grome.dev
  
.SYNOPSIS
  POC/Workaroud for BlackLotus exploit. Checks when last firmware was updated and gets hotfixes. 
#>

function Update-HotFix {
    $hotfixes = Get-HotFix
    
    foreach ($hotfix in $hotfixes) {
        $update = Get-WmiObject -Class Win32_QuickFixEngineering -Filter "HotFixID = '$($hotfix.HotfixId)'"
    
        if ($update.InstalledOn -ne $hotfix.InstalledOn) {
            Write-Host "Checking for update $($hotfix.HotfixId)..."
            try {
                $download = Invoke-WebRequest -Uri $hotfix.URL -OutFile "$($hotfix.HotfixId).msu" -ErrorAction Stop
                Write-Host "Downloaded $($hotfix.HotfixId) successfully."
                $install = Start-Process -FilePath "wusa.exe" -ArgumentList "/quiet $($hotfix.HotfixId).msu" -Wait -PassThru
                if ($install.ExitCode -eq 0) {
                    Write-Host "Installed $($hotfix.HotfixId) successfully."
                }
                else {
                    Write-Host "Failed to install $($hotfix.HotfixId). Exit code $($install.ExitCode)."
                }
            }
            catch {
                Write-Host "Failed to download $($hotfix.HotfixId). Error message: $($Error[0].Exception.Message)"
            }
        }
        else {
            Write-Host "Update $($hotfix.HotfixId) is already installed."
        }
    }
}
    
function Get-FirmwareVersion {
    # Get the firmware version and last update time
    $firmwareVersion = Get-WmiObject Win32_BIOS | Select-Object -ExpandProperty SMBIOSBIOSVersion
    $firmwareLastUpdate = Get-WmiObject Win32_BIOS | Select-Object -ExpandProperty ReleaseDate
    
    # Check if a firmware update has been performed before
    if ($null -ne $firmwareLastUpdate) {
        Write-Host "Firmware $firmwareVersion and was last updated on $firmwareLastUpdate."
        
        # Check if the firmware was last updated before January 11, 2023
        $firmwareLastUpdateFixedString = $firmwareLastUpdate.Substring(0, 14)
        $updateThresholdFixedString = "20230111000000"
        if ($firmwareLastUpdateFixedString -lt $updateThresholdFixedString) {
            Write-Warning "WARNING: Hey idiot! Du har ikke opdateret din firmware siden jan.  11, 2023."
            Write-Host "Updating Hotfix"
            try {
                Update-HotFix
            }
            catch {
                Write-Error "An error occurred while updating the hotfix: $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Host "No firmware updates have been performed on this device."
    }
}
Get-FirmwareVersion

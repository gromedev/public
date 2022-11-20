<#
.SYNOPSIS
    Detection script: checks if:
        BitLocker is enabled.
        Windows Hello is enabled.

.REQUIREMENTS
    Run this script using the logged-on credentials: No
    Enforce script signature check: No
    Run script in 64-bit PowerShell: Yes
#>

$BitLockerStatus = Get-Bitlockervolume


if($BitLockerStatus.ProtectionStatus -eq 'On' -and $BitLockerStatus.EncryptionPercentage -eq '100'){
    if((Test-Path $registryPath)) {
        if(Get-ItemProperty -Path $registryPath -Name $registryValueName -ErrorAction Ignore) {
            if((Get-ItemPropertyValue -Path $registryPath -Name $registryValueName -ErrorAction Ignore)-eq $registryValueData) {
                Write-Host "Windows Hello for Business is required"
                exit 0
            }
            else {
                Write-Host "Windows Hello for Business is currently not required"
                exit 1 
            }
        }
        else {
            Write-Host "Windows Hello for Business is currently not required"
            exit 1 
        }
    }
    else {
        Write-Host "Windows Hello for Business is currently not required"
        exit 1
    } 
}




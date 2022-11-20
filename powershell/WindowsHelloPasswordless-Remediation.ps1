<#
.SYNOPSIS
    Remediation script: if detection script does NOT find Windows Hello is active; then configures Windows Hello passwordless mode. 

.REQUIREMENTS
    Run this script using the logged-on credentials: No
    Enforce script signature check: No
    Run script in 64-bit PowerShell: Yes
#>

$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$registryValueName = "scforceoption"
$registryValueData = "1"

try {
    if(!(Test-Path $registryPath)) {
        New-Item -Path $registryPath -Force
        New-ItemProperty -Path $registryPath -Name $registryValueName -Value $registryValueData -PropertyType DWORD -Force
        Write-Host "Successfully configured Windows Hello for Business as required" 
    }
    else {
        New-ItemProperty -Path $registryPath -Name $registryValueName -Value $registryValueData -PropertyType DWORD -Force
        Write-Host "Successfully configured Windows Hello for Business as required" 
    }
}
catch {
    $errorMessage = $_.Exception.Message
    Write-Error $errorMessage
    exit 1 
}
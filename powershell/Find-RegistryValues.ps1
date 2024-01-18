$keyPattern = "*dpa*"

$RegPaths = @(
    # Defender
    'HKLM:\SOFTWARE\Microsoft\',
    'HKCU:\SOFTWARE\Microsoft\',
    'HKLM:\SOFTWARE\Policies\',
    'HKLM:\SYSTEM\CurrentControlSet\'
)

$keyPattern = "*dpa*"

foreach ($RegPath in $RegPaths) {
    Write-Host "Searching in registry path: $RegPath" -ForegroundColor Red

    if (Test-Path -Path $RegPath) {
        Get-ChildItem -Path $RegPath -Recurse | ForEach-Object {
            $subkeyPath = $_.PSPath
            $regKey = Get-ItemProperty -Path $subkeyPath -ErrorAction SilentlyContinue

            $regKey.PSObject.Properties | ForEach-Object {
                if ($_.Name -like $keyPattern) {
                    Write-Host "$subkeyPath" -NoNewline
                    Write-Host "\"$($_.Name) = $($_.Value)\"" -ForegroundColor Green
                }
            }
        }
    } else {
        Write-Host "Registry path not found" -ForegroundColor Yellow
    }
}

<#
$RegPaths = @(
    # Defender
    'HKLM:\SOFTWARE\Microsoft\Windows Defender',
    'HKLM:\SOFTWARE\Microsoft\Windows Defender Security Center',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard',
    'HKLM:\SYSTEM\CurrentControlSet\Services\WinDefend',
    'HKLM:\SYSTEM\CurrentControlSet\Services\SecurityHealthService',
    'HKLM:\SYSTEM\CurrentControlSet\Services\wscsvc',
    'HKLM:\SYSTEM\CurrentControlSet\Services\DPS\Parameters',

    # Intune
    'HKLM:\SOFTWARE\Microsoft\MdmDiagnostics',
    'HKLM:\SOFTWARE\Policies\Microsoft\Intune',
    'HKCU:\Software\Microsoft\Intune',

    # General
    'HKLM:\SOFTWARE\Microsoft\Policies',
    'HKLM:\SOFTWARE\Microsoft\PolicyManager',

    # Windows
    'HKLM:\SOFTWARE\Policies\Microsoft\SystemCertificates',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate',
    'HKLM:\SYSTEM\CurrentControlSet\Services\MSiSCSI\Parameters',
    'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy',

    # Additional
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName',
    'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName',
    'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName\ComputerName',
    'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName\ActiveComputerName',
    'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName\ComputerNamePhysicalDnsDomain',
    'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName\ActiveComputerNamePhysicalDnsDomain',
    'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation',
    'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters',
    'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces',
    'HKLM:\SYSTEM\CurrentControlSet\Services\Winsock\Parameters',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Startup',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logon',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logoff',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\GPOLink\Local'
)
#>

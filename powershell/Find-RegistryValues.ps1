$RegPath = 'HKLM:\SOFTWARE\Microsoft\Windows Defender'
$keyPattern = "*Dpa*"

Get-ChildItem -Path $RegPath -Recurse | ForEach-Object {
    $subkeyPath = $_.PSPath
    $regKey = Get-ItemProperty -Path $subkeyPath -ErrorAction SilentlyContinue

    $regKey.PSObject.Properties | ForEach-Object {
        if ($_.Name -like $keyPattern) {
            Write-Host "$subkeyPath\$($_.Name) = $($_.Value)"
        }
    }
}

# Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection\DpaDisabled = 0

<# 
$RegKey = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection')
$key = "*Dpa*"

$RegKey.PSObject.Properties | ForEach-Object {
  If($_.Name -like $key){
    Write-Host $_.Name ' = ' $_.Value
  }
}
#>

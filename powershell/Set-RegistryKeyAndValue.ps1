$registryPath = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Options\General"
$name = "DelegateWastebasketStyle"
$value = "4"
$type = "DWORD"

IF(!(Test-Path $registryPath))
{
    New-Item -Path $registryPath -Force | Out-Null
}

New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType $type -Force | Out-Null

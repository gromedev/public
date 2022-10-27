<#
.AUTHOR
  thomas@grome.dev 
  
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Synaptics\SynTP\TouchPadRMIHID2cTM3336-4]
"NotifyDriverFirstLoadState"=dword:00000000
"DisableDevice"=dword:00000000
"2FingerTapAction"=dword:00000002
"2FingerTapPluginID"=""
"3FingerTapPluginID"=""
"MultiFingerTapFlags"=dword:00000003
"3FingerTapAction"=dword:00000004
"3FingerTapPluginActionID"=dword:00000000
#>

$registryPath = "HKCU:\Software\Synaptics\SynTP\TouchPadRMIHID2cTM3336-4"
$type = "DWORD"

IF(!(Test-Path $registryPath))
{
    New-Item -Path $registryPath -Force | Out-Null
}

New-ItemProperty -Path $registryPath -Name "NotifyDriverFirstLoadState" -Value "0" -PropertyType $type -Force | Out-Null
New-ItemProperty -Path $registryPath -Name "DisableDevice" -Value "0" -PropertyType $type -Force | Out-Null
New-ItemProperty -Path $registryPath -Name "2FingerTapAction" -Value "2" -PropertyType $type -Force | Out-Null
New-ItemProperty -Path $registryPath -Name "2FingerTapPluginID" -Value "" -PropertyType "" -Force | Out-Null
New-ItemProperty -Path $registryPath -Name "3FingerTapPluginID" -Value "" -PropertyType "" -Force | Out-Null
New-ItemProperty -Path $registryPath -Name "MultiFingerTapFlags" -Value "3" -PropertyType $type -Force | Out-Null
New-ItemProperty -Path $registryPath -Name "3FingerTapAction" -Value "4" -PropertyType $type -Force | Out-Null
New-ItemProperty -Path $registryPath -Name "3FingerTapPluginActionID" -Value "0" -PropertyType $type -Force | Out-Null

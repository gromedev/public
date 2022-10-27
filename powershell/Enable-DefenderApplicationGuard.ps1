$RegLoc = "HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides"

New-Item -path HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft

New-Item -path HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement

New-Item -Path HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides

New-ItemProperty -Path $RegLoc -Name 3457697930 -PropertyType Dword -Value 1

New-ItemProperty -Path $RegLoc -Name 94539402 -PropertyType Dword -Value 1

Get-ScheduledTask -TaskName "ReconcileFeatures" -TaskPath "\Microsoft\Windows\Flighting\FeatureConfig\" | Start-ScheduledTask

# Enable Windows Defender Application Guard with no reboot switch

Enable-WindowsOptionalFeature -Online -FeatureName Windows-Defender-ApplicationGuard -NoRestart

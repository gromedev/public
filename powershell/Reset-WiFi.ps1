netsh winsock reset
netsh int ip reset
ipconfig /renew
ipconfig /flushdns
netcfg -d
Get-PnpDevice -class net | ? Status -eq Unknown | Select FriendlyName,InstanceId
$Devs = Get-PnpDevice -class net | ? Status -eq Unknown | Select FriendlyName,InstanceId

ForEach ($Dev in $Devs) {
    Write-Host "Removing $($Dev.FriendlyName)" -ForegroundColor Cyan
    $RemoveKey = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($Dev.InstanceId)"
    Get-Item $RemoveKey | Select-Object -ExpandProperty Property | %{ Remove-ItemProperty -Path $RemoveKey -Name $_ -Verbose }
}
Write-Host "Done.  Please restart!" -ForegroundColor Green

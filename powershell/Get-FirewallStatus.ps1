# Checks if firewall is enabled or disabled
if (((Get-NetFirewallProfile | select name,enabled) | where { $_.Enabled -eq $True } | measure ).Count -eq 3) {Write-Host "OK" -ForegroundColor Green} else {Write-Host "OFF" -ForegroundColor Red}

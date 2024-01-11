# Install-Module -Name Firewall-Manager -force
# Import-Module Firewall-Manager -force
# Get-NetFirewallRule |Format-Table|more
# Get-NetFirewallRule -DisplayName "*NetBIOS" |Format-Table|more
$RuleName = "AllowRemoteConnectionToNetBIOS"
$path = "C:\temp\"
#Export-FirewallRules -Name $RuleName -CSVFile "$path$RuleName.csv"
#Export-FirewallRules -Name $RuleName -JSON "$path$RuleName.json"
Import-FirewallRules -JSON "C:\temp\AllowRemoteConnectionToNetBIOS.json"

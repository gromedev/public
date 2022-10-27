#$fire=Get-NetFirewallprofile -profile domain,public,private 
#$fire | Export-Csv "C:\temp\FwRulesAll.csv" -NoTypeInfo -Delim ";"


$fire=Get-NetFirewallprofile | Get-NetFirewallRule | Select-Object -Property DisplayName,Enabled,Profile,Direction
$fire | Export-Csv "C:\temp\FwRulesAllProfiles.csv" -NoTypeInfo -Delim ";"

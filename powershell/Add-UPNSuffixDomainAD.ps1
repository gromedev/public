<#
After adding AD to AzureAD...
#># Add UPN suffix in Active Directory
Get-ADForest | Set-ADForest -UPNSuffixes @{add="MSDx451484.onmicrosoft.com"}
Get-ADForest | Format-List UPNSuffixes

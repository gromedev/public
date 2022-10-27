Enable-ADOptionalFeature -Identity 'CN=Recycle Bin Feature,CN=Optional Features,CN=Directory Service,CN=Windows NT,CN=Services,CN=Configuration,DC=dom01,DC=local' -Scope ForestOrConfigurationSet -Target 'dom01.local'

#Get-ADUser -Filter 'Name -Like "*test*"'|Remove-ADUser -Confirm:$false
#Get-ADObject -Filter 'Name -Like "*test*"' -IncludeDeletedObjects | Restore-ADObject

$user = "*Administrator*"
Get-LocalGroup | Where-Object { (Get-LocalGroupMember $_.Name).Name -like $user }

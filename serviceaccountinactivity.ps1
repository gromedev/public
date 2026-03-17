$cutoff = (Get-Date).AddDays(-90)
Get-ADServiceAccount -Filter * -Properties lastLogonTimestamp |
    Where-Object { [DateTime]::FromFileTime($_.lastLogonTimestamp) -lt $cutoff } |
    Select-Object Name, @{N='LastLogon';E={[DateTime]::FromFileTime($_.lastLogonTimestamp)}}

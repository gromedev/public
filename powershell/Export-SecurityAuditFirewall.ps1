# Enable auditing
# auditpol /set /subcategory:"Filtering Platform Connection" /success:disable /failure:disable

# Event IDs for failed firewall rule import(s)
$eventIDs = 4950,4951,4952,4953,4954,4955,4956,4957,4958,4959 

# Get events from the past hour with the specified Event IDs
$events = Get-EventLog -LogName Security -After ((Get-Date).AddHours(-1)) | Where-Object { $eventIDs -contains $_.EventID }

# Export the events to a CSV file
$events | Export-Csv -Path "C:\temp\SecurityEventsNew2.csv" -NoTypeInformation

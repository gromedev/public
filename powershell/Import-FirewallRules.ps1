#Exports current firewall settings
netsh advfirewall export "C:\temp\OLDfirewallrules.wfw"

#Enables audit (if not all firewall settings can be imported)
auditpol /set /subcategory:"Filtering Platform Connection" /success:enable /failure:enable

#Imports new firewall settings
netsh advfirewall import "C:\path\to\your\firewallrules.wfw"

#Disables audit again
auditpol /set /subcategory:"Filtering Platform Connection" /success:disable /failure:disable

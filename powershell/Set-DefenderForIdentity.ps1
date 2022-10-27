<#
Author: tmg@venzo.com
Description: Configures Defender for Identity on Stand-Alone Server.
#>

# Open Internet ports required by Defender for Identity
#SSL (*.atp.azure.com)	TCP	443
New-NetFirewallRule -DisplayName "Allow DfI SSL 443 In" -Direction inbound -Profile Any -Action Allow -LocalPort 443 -Protocol TCP
New-NetFirewallRule -DisplayName "Allow DfI SSL 443 Out" -Direction outbound -Profile Any -Action Allow -LocalPort 443 -Protocol TCP

# Open Internal ports required by Defender for Identity
New-NetFirewallRule -DisplayName "Allow DfI DNS TCP 53" -Direction outbound -Profile Any -Action Allow -LocalPort 53 -Protocol TCP
New-NetFirewallRule -DisplayName "Allow DfI SMB, CIFS, SAM-R TCP 445" -Direction outbound -Profile Any -Action Allow -LocalPort 445 -Protocol TCP
New-NetFirewallRule -DisplayName "Allow DfI SMB, CIFS, SAM-R UDP 445" -Direction outbound -Profile Any -Action Allow -LocalPort 445 -Protocol UDP
New-NetFirewallRule -DisplayName "Allow DfI RADIUS UDP 1813" -Direction inbound -Profile Any -Action Allow -LocalPort 1813 -Protocol UDP

# Open Localhosts ports required by Defender for Identity (Required for Sensor Service updater)
New-NetFirewallRule -DisplayName "Allow DfI SSL (localhost)	TCP	444" -Direction outbound -Profile Any -Action Allow -LocalPort 444 -Protocol TCP

# Open NNR ports required by Defender for Identity (Required for Sensor Service updater)
New-NetFirewallRule -DisplayName "Allow DfI NTLM over RPC TCP Port 135" -Direction outbound -Profile Any -Action Allow -LocalPort 135 -Protocol TCP
New-NetFirewallRule -DisplayName "Allow DfI NetBIOS	UDP	137" -Direction outbound -Profile Any -Action Allow -LocalPort 137 -Protocol UDP
New-NetFirewallRule -DisplayName "Allow DfI RDP (only the first packet of Client hello)	TCP	3389" -Direction outbound -Profile Any -Action Allow -LocalPort 3389 -Protocol TCP

# Verify firewall rules
$rule = `
"Allow DfI SSL 443 In", `
"Allow DfI SSL 443 Out", `
"Allow DfI DNS TCP 53",`
"Allow DfI SMB, CIFS, SAM-R TCP 445", `
"Allow DfI SMB, CIFS, SAM-R UDP 445", `
"Allow DfI RADIUS UDP 1813", `
"Allow DfI SSL (localhost)	TCP	444", `
"Allow DfI NTLM over RPC TCP Port 135", `
"Allow DfI NetBIOS	UDP	137", `
"Allow DfI RDP (only the first packet of Client hello)	TCP	3389"
Get-NetFirewallRule -DisplayName $rule | ft -Property Name, DisplayName, @{Name='Protocol';Expression={($PSItem | Get-NetFirewallPortFilter).Protocol}}, @{Name='LocalPort';Expression={($PSItem | Get-NetFirewallPortFilter).LocalPort}}, @{Name='RemotePort';Expression={($PSItem | Get-NetFirewallPortFilter).RemotePort}}, @{Name='RemoteAddress';Expression={($PSItem | Get-NetFirewallAddressFilter).RemoteAddress}}, Enabled, Profile, Direction, Action

# Required for adding machine to gMSA sroup
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 
Install-WindowsFeature RSAT-AD-PowerShell

# Add machine to gMSA group
Add-ADGroupMember -Identity "mdiActionAccounts" -Members mdiAction01$

# Install MDI Sensor
$InstallDir = "\\DC01\public\MDI"
$AgentTemp = "Azure ATP sensor Setup.exe"
Set-Location $InstallDir
Start-Process -FilePath $AgentTemp -ArgumentList @(
    'NetFrameworkCommandLineArguments="/q',
    'AccessKey="1nT7915R0NIt9vp9Ax/5P7MHxjjnDiVZcz4Vjzl03gj3Ah3fuQMy9rYA99YecM9usPkg1l4y5wCrhSz0vg1RQg=="'
)

##requires -module vmware.powercli
<#
.SYNOPSIS
    It is a way of reconfiguring ESXi hosts via a vCenter connection and VMware PowerCli
.AUTHOR
    thomas@grome.dev
.DESCRIPTION
    This script is able to reconfigure ESX hosts in the following ways:
    - Start SSH service
    - Stop SSH service
    - Configure remote Syslog
    - Configure SNMP
.NOTES
    Requires VMware.Powercli
.LINK
    https://developer.vmware.com/docs/15315/powercli-user-s-guide
.EXAMPLE
    Run the script - no individual functions exposed. No need to .source.
#>

  
$vcenter = "srv-vcenter01.adsrv.local" # Enter url to vcenter
$vcenterCred = Get-Credential -Message "Enter your vCenter Server Credentials"
$esxiCred = Get-Credential -Message "Enter your ESXi root credentials"
$RemoteSyslogHost = 'udp://10.0.0.1:514' #enter udp

#  Connect to vCenter 
  
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false `
    -DefaultVIServerMode Multiple | Out-Null
Connect-VIServer -Server $vcenter -Credential $vcenterCred
  

#  Get SNMP Settings 
$GetSnmp = { 
    $myHosts = Get-VMHost #| Out-GridView -OutputMode Multiple
    Connect-ViServer $myHosts -Credential $esxiCred
    $hostSNMP = Get-VMHostSnmp -Server $myHosts.Name
    Write-Host "`nThe current settings for your ESXi hosts are as follows:" `
        -ForegroundColor Blue
    $hostSNMP | Select-Object VMHost,Enabled,Port,ReadOnlyCommunities | `
        Format-Table -AutoSize
}


#  Set SNMP Settings 
$SetSnmp = {
    $communityString = "public"
    Write-Host "SNMP community string entered is: $communityString `n" `
        -ForegroundColor Blue
    Write-Host "Updated settings for your ESXi hosts are as follows: `n" `
        -ForegroundColor Green
    $hostSNMP = Set-VMHostSNMP $hostSNMP -Enabled:$true `
        -ReadOnlyCommunity $communityString
    $hostSNMP | Select-Object VMHost,Enabled,Port,ReadOnlyCommunities | `
        Format-Table -AutoSize
    $snmpStatus = $myHosts| Get-VMHostService | `
        Where-Object{$_.Key -eq "snmpd"} 
    
    ForEach ($i in $snmpStatus) {
        if ($snmpStatus.running -eq $true) {
            $i | Restart-VMHostService -Confirm:$false | Out-Null
        }
        else {
            $i | Start-VMHostService -Confirm:$false | Out-Null
        }
    }
    
    Write-Host "SNMP service has been started on the ESXi host(s)." `
        -ForegroundColor Blue
    $myHosts | Get-VMHostService | Where-Object{$_.Key -eq "snmpd"} | `
        Select-Object VMHost,Key,Running | Format-Table -AutoSize
}

# Set remote syslog
$SetRemoteSyslog = {
    [hashtable]$NewSettings = @{'Config.HostAgent.log.level'='info';'Syslog.global.logHost'=$RemoteSyslogHost}

    ForEach ($_setting in $NewSettings.Keys) {
        Get-VMHost | Get-AdvancedSetting -Name $_setting | Set-AdvancedSetting -Value $NewSettings[$_setting] -Confirm:$false
    }
}

$DisConnect = {
    Disconnect-VIServer -Server * -Confirm:$false
}

# Enable SSH
$EnableSSH = {
    Get-VMHost | Foreach {Start-VMHostService -HostService ($_ | Get-VMHostService | Where { $_.Key -eq "TSM-SSH"} )}
}

# Disable SSH
$DisableSSH = {
    Get-VMHost | Foreach {Stop-VMHostService -HostService ($_ | Get-VMHostService | Where { $_.Key -eq "TSM-SSH"} )}
}

$Menu = {
    Clear-Host
    Write-Output -InputObject @"
1. Enable SSH
2. Disable SSH
3. Get SNMP Settings
4. Enable SNMP
5. Set Remote Syslog server
6. Disconnect VMware Hosts
"@
[int]$option = Read-Host -Prompt "Please select option:"
Switch ($option) {
    1 {$EnableSSH.Invoke(); $Menu.Invoke()}
    2 {$DisableSSH.Invoke(); $Menu.Invoke()};
    3 {$GetSnmp.Invoke(); $Menu.Invoke()};
    4 {$SetSnmp.Invoke(); $Menu.Invoke()};
    5 {$SetRemoteSyslog.Invoke(); $Menu.Invoke()};
    6 {$DisConnect.Invoke(); $Menu.Invoke()}
    default {$Menu.Invoke()}
}

}

$Menu.Invoke()

<#
.SYNOPSIS
    Enables winRM and PSSession on remote device
.AUTHOR
    thomas@grome.dev
.LINK
    https://developer.vmware.com/docs/15315/powercli-user-s-guide

#>

$ADComputers = Get-ADComputer -Filter {enabled -eq $true}

[System.Collections.Generic.List[System.Management.Automation.Job]]$Jobz = @()

$ADComputers | ForEach-Object {

    $jobz.Add($(Invoke-Command -ComputerName $_.DNSHostName -ScriptBlock $sb3 -Argumentlist @($_.DNSHostName) -AsJob))
}
$jobz | % {$_ | Receive-Job}

[scriptblock]$sbfw = {
function Add-FirewallRule {
   param( 
      $name,
      $tcpPorts,
      $appName = $null,
      $serviceName = $null
   )
    $fw = New-Object -ComObject hnetcfg.fwpolicy2 
    $rule = New-Object -ComObject HNetCfg.FWRule
        
    $rule.Name = $name
    if ($appName -ne $null) { $rule.ApplicationName = $appName }
    if ($serviceName -ne $null) { $rule.serviceName = $serviceName }
    $rule.Protocol = 6 #NET_FW_IP_PROTOCOL_TCP
    $rule.LocalPorts = $tcpPorts
    $rule.Enabled = $true
    $rule.Grouping = "@firewallapi.dll,-23255"
    $rule.Profiles = 7 # all
    $rule.Action = 1 # NET_FW_ACTION_ALLOW
    $rule.EdgeTraversal = $false
    
    $fw.Rules.Add($rule)
}
# From http://blogs.msdn.com/b/tomholl/archive/2010/11/08/adding-a-windows-firewall-rule-using-powershell.aspx

Add-FirewallRule "Windows Remote Management HTTP/SSL" "5986" $null $null
Add-FirewallRule "SMB" "445" $null $null
}

$ADComputers = Get-ADComputer -Filter {enabled -eq $true}

[System.Collections.Generic.List[System.Management.Automation.Job]]$Jobz = @()

$ADComputers | ForEach-Object {

    $jobz.Add($(Invoke-Command -ComputerName $_.DNSHostName -ScriptBlock $sbfw -Argumentlist @($_.DNSHostName) -AsJob))
}
$jobz | % {$_ | Receive-Job}

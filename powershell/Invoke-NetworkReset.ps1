<#
.SYNOPSIS
    This script attempts to fix being unable to change firewall domain profiles from public to private.
.AUTHOR
    tmg@venzo.com
.EXAMPLE
    Run the script - no individual functions exposed. No need to .source.
#>

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [System.Windows.Forms.Messagebox]::Show("Not running as administrator!");
    $confirmation = Read-Host "Enter y to launch powershell as administrator"
    if ($confirmation -eq 'y') {
        start-process powershell -verb runas
    }
}

function Show-Menu {
     param (
        [string]$Title = ‘Firewall fix. Attempt Option 1 first. If fail, then option 2. Reboot on completition and ’
    )
    Clear-Host
    Write-Host "================ $Title ================"
    Write-Host “1: Set firewall outbound rule to allow.”
    Write-Host “2: Run entire script.”
    Write-Host “3: Reset network settings.”
    Write-Host “4: Invoke Network adapter fix.”
    Write-Host “5: Set IPs to dynamic.”
    Write-Host “6: Remove DNS Suffixes”
    Write-Host “Q: Press ‘Q’ to quit.”
}

function Set-FirewallOutboundRules {
    try {
        Write-Host "Attempting to set public domain profile outbound action to allow"
        Set-NetFirewallProfile -Profile Public -DefaultOutboundAction Allow
    }
    catch {
        Write-Host "Attempting to set all domain profiles outbound actions to allow"
        Set-NetFirewallProfile -DefaultOutboundAction Allow
    }

    get-NetFirewallProfile
    Write-Host "Make sure that DefaultOutboundAction : Allow -- otherwise return to menu and select option 2 (run entire script)"
}

function Invoke-NetReset {
    write-host "Resetting network settings"
    ipconfig /renew
    ipconfig /flushdns
    start-process cmd.exe -argumentlist "/c 'netsh winsock reset'"
    start-process cmd.exe -argumentlist "/c 'netsh winsock reset catalog'"
    start-process cmd.exe -argumentlist "/c 'netsh int ipv4 reset reset.log'"
    start-process cmd.exe -argumentlist "/c 'netsh int ipv6 reset reset.log'"

    Write-Host "Network settings reset. I recommend you reboot and run script again"
    $confirmation = Read-Host "Enter y to reboot."
        if ($confirmation -eq 'y') {
            Restart-Computer -Force
    }
}

function Remove-DNSSuffix {
    write-host "Removing DNS suffixes"
    Set-DnsClientGlobalSetting -SuffixSearchList @("")
}

function Invoke-NetAdapterFix {
    Disable-NetAdapter -Name "*" -Confirm:$false
    Enable-NetAdapter -Name "*"
    Set-NetConnectionProfile -NetworkCategory Private
}

function Set-DynamicIPs {
    $NICs = Get-WMIObject Win32_NetworkAdapterConfiguration | where{$_.IPEnabled -eq “TRUE”}
        Foreach($NIC in $NICs) {
        $NIC.EnableDHCP()
        $NIC.SetDNSServerSearchOrder()
    }
}

function Invoke-FirewallFix {
    try {
        Get-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop
        write-host "Connection working." -ForegroundColor Green
    }
    catch {
        write-host "Connection not working. Attempting remediation." -ForegroundColor Red
        Invoke-NetReset -force -verbose

        write-host "Setting dynamic IPs" -ForegroundColor Red
        Set-DynamicIPs -force -verbose

        write-host "Resetting network adapaters" -ForegroundColor Red
        Invoke-NetAdapterFix -force -verbose

        write-host "Clearing DNS Suffixes" -ForegroundColor Red
        Remove-DNSSuffix -force -verbose
    }
}

function Remove-DNSSuffix {
        write-host "Removing DNS suffixes"
        start-sleep 10
        Set-DnsClientGlobalSetting -SuffixSearchList @("")
        try {
            Set-NetConnectionProfile -NetworkCategory Private
        }
        catch {
            Write-Host "Error changing domain. Reboot and try again."
            $confirmation = Read-Host "Enter y to reboot."
            if ($confirmation -eq 'y') {
                Start-Process powershell -verb runas
        }
    }
}

 #Main menu loop
 do {
     Show-Menu
     $input = Read-Host "Please make a selection"
     Clear-Host
     switch ($input) {
         '1' {Set-FirewallOutboundRules;break}
         '2' {Invoke-FirewallFix -force; break}
         '3' {Invoke-NetReset; break}
         '4' {Invoke-NetAdapterFix; break}
         '5' {Set-DynamicIPs; break}
         '6' {Remove-DNSSuffix; break}
         'q' {break} # do nothing
         default{
             Write-Host "You entered '$input'" -ForegroundColor Red
             Write-Host "Please select one of the choices from the menu." -ForegroundColor Red}
     }
     Pause
 } until ($input -eq 'q')

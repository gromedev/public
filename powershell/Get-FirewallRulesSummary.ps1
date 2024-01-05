Get-NetFirewallRule | ForEach-Object {
    $rule = $_
    $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule
    $addressFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule

    [PSCustomObject]@{
        Name = $rule.Name
        DisplayName = $rule.DisplayName
        Description = $rule.Description
        Enabled = $rule.Enabled
        Profile = $rule.Profile.ToString()
        Direction = $rule.Direction
        Action = $rule.Action
        Priority = $rule.Profile.ToString() -replace "Any","255" # Defaulting 'Any' to the lowest priority
        Group = $rule.Group
        EdgeTraversalPolicy = $rule.EdgeTraversalPolicy
        Protocol = $portFilter.Protocol
        LocalPort = $portFilter.LocalPort
        RemotePort = $portFilter.RemotePort
        RemoteAddress = $addressFilter.RemoteAddress
        InterfaceType = $rule.InterfaceType
        ServiceName = $rule.serviceName
        ApplicationPackageName = $rule.ApplicationPackageName
    }
} | Export-Csv -Path "C:\temp\RN-firewallRulesNEW.csv" -NoTypeInformation

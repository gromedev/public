<#
    ACTIVE DIRECTORY TEST DATA SCRIPT
    Creates test data in on-premises Active Directory for security posture analysis.

    Includes:
    - Organizational Units (OUs) - hierarchical structure
    - Users - regular users, service accounts, admin accounts
    - Groups - security groups, nested groups, privileged groups
    - Computers - simulated domain-joined systems
    - Attack Paths via misconfigurations:
        - Unconstrained delegation
        - Constrained delegation (Kerberos & Protocol Transition)
        - Resource-based constrained delegation (RBCD)
        - Kerberoastable service accounts (SPNs)
        - AS-REP roastable users (no preauth required)
        - ACL misconfigurations (GenericAll, WriteDacl, WriteOwner, etc.)
        - Nested group memberships to privileged groups
        - GPO abuse paths
        - AdminSDHolder inheritance
        - LAPS readable by non-admins
        - Shadow Credentials (msDS-KeyCredentialLink writable)
#>

#Requires -Version 5.1
#Requires -Modules ActiveDirectory

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive CLI script')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test data')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test script')]
[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [ValidateSet('Create', 'AttackPaths', 'Cleanup', 'Status')]
    [string]$Action,
    [string]$TestPrefix = 'Alpenglow',
    [int]$UserCount = 100,
    [int]$GroupCount = 30,
    [int]$ComputerCount = 20,
    [int]$NestingDepth = 5
)

#region Configuration

$Config = @{
    UserCount       = $UserCount
    GroupCount      = $GroupCount
    ComputerCount   = $ComputerCount
    NestingDepth    = $NestingDepth

    # OU Structure
    OUStructure     = @(
        'Corporate'
        'Corporate/Users'
        'Corporate/Users/Employees'
        'Corporate/Users/Contractors'
        'Corporate/Users/ServiceAccounts'
        'Corporate/Computers'
        'Corporate/Computers/Workstations'
        'Corporate/Computers/Servers'
        'Corporate/Groups'
        'Corporate/Groups/Security'
        'Corporate/Groups/Distribution'
        'IT'
        'IT/AdminUsers'
        'IT/AdminGroups'
        'IT/ServiceAccounts'
        'Tier0'
        'Tier0/Admins'
        'Tier0/ServiceAccounts'
        'Tier0/PAW'
    )

    # Well-known privileged groups to create paths to
    PrivilegedGroups = @(
        'Domain Admins'
        'Enterprise Admins'
        'Schema Admins'
        'Administrators'
        'Account Operators'
        'Backup Operators'
        'Server Operators'
        'Print Operators'
        'DnsAdmins'
    )

    # Departments for user generation
    Departments     = @('Finance', 'HR', 'Engineering', 'Sales', 'Marketing', 'IT', 'Legal', 'Operations')

    # Titles for user generation
    Titles          = @('Analyst', 'Manager', 'Director', 'Engineer', 'Specialist', 'Coordinator', 'Administrator', 'Consultant')
}

$StateFile = Join-Path $PSScriptRoot 'ADTestData-State.json'

# Track created objects for cleanup
$script:CreatedObjects = @{
    Users         = [System.Collections.ArrayList]@()
    Groups        = [System.Collections.ArrayList]@()
    Computers     = [System.Collections.ArrayList]@()
    OUs           = [System.Collections.ArrayList]@()
    ACLChanges    = [System.Collections.ArrayList]@()
    GPOs          = [System.Collections.ArrayList]@()
    AttackPaths   = [System.Collections.ArrayList]@()
}

#endregion

#region Helper Functions

function Get-DomainDN {
    return (Get-ADDomain).DistinguishedName
}

function Get-TestOUPath {
    param([string]$OUName)
    $domainDN = Get-DomainDN
    return "OU=$OUName,OU=$($Config.OUStructure[0]),$domainDN"
}

function Get-State {
    if (Test-Path $StateFile) {
        $loaded = Get-Content $StateFile -Raw | ConvertFrom-Json -AsHashtable
        return @{
            users       = [System.Collections.ArrayList]@($loaded.users ?? @())
            groups      = [System.Collections.ArrayList]@($loaded.groups ?? @())
            computers   = [System.Collections.ArrayList]@($loaded.computers ?? @())
            ous         = [System.Collections.ArrayList]@($loaded.ous ?? @())
            aclChanges  = [System.Collections.ArrayList]@($loaded.aclChanges ?? @())
            gpos        = [System.Collections.ArrayList]@($loaded.gpos ?? @())
            attackPaths = [System.Collections.ArrayList]@($loaded.attackPaths ?? @())
        }
    }
    return @{
        users       = [System.Collections.ArrayList]@()
        groups      = [System.Collections.ArrayList]@()
        computers   = [System.Collections.ArrayList]@()
        ous         = [System.Collections.ArrayList]@()
        aclChanges  = [System.Collections.ArrayList]@()
        gpos        = [System.Collections.ArrayList]@()
        attackPaths = [System.Collections.ArrayList]@()
    }
}

function Save-State($State) {
    $State | ConvertTo-Json -Depth 10 | Set-Content $StateFile -Force
}

function New-RandomPassword {
    param([int]$Length = 16)
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*'
    return -join ((1..$Length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

function Get-RandomElement {
    param([array]$Array)
    return $Array[(Get-Random -Maximum $Array.Count)]
}

#endregion

#region OU Creation Functions

function New-TestOUStructure {
    param(
        [string]$Prefix,
        [hashtable]$State
    )

    Write-Host "`n=== Creating OU Structure ===" -ForegroundColor Cyan

    $domainDN = Get-DomainDN

    foreach ($ouPath in $Config.OUStructure) {
        $parts = $ouPath -split '/'
        $currentPath = $domainDN

        foreach ($part in $parts) {
            $ouName = if ($part -eq $Config.OUStructure[0]) { "$Prefix-$part" } else { $part }
            $fullPath = "OU=$ouName,$currentPath"

            try {
                $existing = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$fullPath'" -ErrorAction SilentlyContinue
                if (-not $existing) {
                    New-ADOrganizationalUnit -Name $ouName -Path $currentPath -ProtectedFromAccidentalDeletion $false
                    Write-Host "  + OU: $ouName" -ForegroundColor Green
                    $null = $State.ous.Add(@{
                        Name = $ouName
                        DN   = $fullPath
                        Path = $ouPath
                    })
                }
                else {
                    Write-Host "  = OU exists: $ouName" -ForegroundColor Gray
                }
                $currentPath = $fullPath
            }
            catch {
                Write-Warning "  ! Failed to create OU $ouName`: $_"
            }
        }
    }
}

#endregion

#region User Creation Functions

function New-TestUser {
    param(
        [string]$Prefix,
        [string]$Department,
        [string]$Title,
        [string]$OUPath,
        [switch]$ServiceAccount,
        [switch]$NoPreAuth,
        [string]$SPN
    )

    $id = (New-Guid).ToString().Substring(0, 8)
    $firstName = Get-RandomElement @('James', 'Mary', 'John', 'Patricia', 'Robert', 'Jennifer', 'Michael', 'Linda', 'William', 'Elizabeth', 'David', 'Barbara', 'Richard', 'Susan', 'Joseph', 'Jessica', 'Thomas', 'Sarah', 'Christopher', 'Karen')
    $lastName = Get-RandomElement @('Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez', 'Hernandez', 'Lopez', 'Gonzalez', 'Wilson', 'Anderson', 'Thomas', 'Taylor', 'Moore', 'Jackson', 'Martin')

    $name = if ($ServiceAccount) {
        "svc_$Prefix`_$id"
    }
    else {
        "$Prefix-$firstName.$lastName-$id"
    }

    $samAccountName = $name.Substring(0, [Math]::Min(20, $name.Length))
    $password = New-RandomPassword

    try {
        $userParams = @{
            Name                  = $name
            SamAccountName        = $samAccountName
            UserPrincipalName     = "$samAccountName@$((Get-ADDomain).DNSRoot)"
            GivenName             = if (-not $ServiceAccount) { $firstName } else { $null }
            Surname               = if (-not $ServiceAccount) { $lastName } else { $null }
            DisplayName           = $name
            Department            = $Department
            Title                 = $Title
            Path                  = $OUPath
            AccountPassword       = (ConvertTo-SecureString $password -AsPlainText -Force)
            Enabled               = $true
            PasswordNeverExpires  = $ServiceAccount
            CannotChangePassword  = $ServiceAccount
        }

        # Remove null values
        $userParams = $userParams.GetEnumerator() | Where-Object { $null -ne $_.Value } | ForEach-Object -Begin { $h = @{} } -Process { $h[$_.Key] = $_.Value } -End { $h }

        New-ADUser @userParams

        $user = Get-ADUser -Identity $samAccountName -Properties ObjectGUID, DistinguishedName

        # Set AS-REP roastable if requested
        if ($NoPreAuth) {
            Set-ADAccountControl -Identity $samAccountName -DoesNotRequirePreAuth $true
            Write-Host "  + User (AS-REP Roastable): $name" -ForegroundColor Yellow
        }
        # Set SPN if requested (Kerberoastable)
        elseif ($SPN) {
            Set-ADUser -Identity $samAccountName -ServicePrincipalNames @{Add = $SPN }
            Write-Host "  + User (Kerberoastable): $name [SPN: $SPN]" -ForegroundColor Yellow
        }
        elseif ($ServiceAccount) {
            Write-Host "  + Service Account: $name" -ForegroundColor Cyan
        }
        else {
            Write-Host "  + User: $name" -ForegroundColor Green
        }

        return @{
            ObjectGUID      = $user.ObjectGUID.ToString()
            SamAccountName  = $samAccountName
            DN              = $user.DistinguishedName
            DisplayName     = $name
            IsServiceAccount = $ServiceAccount.IsPresent
            NoPreAuth       = $NoPreAuth.IsPresent
            SPN             = $SPN
            Password        = $password
        }
    }
    catch {
        Write-Warning "  ! Failed to create user $name`: $_"
        return $null
    }
}

function New-TestUsers {
    param(
        [string]$Prefix,
        [int]$Count,
        [hashtable]$State
    )

    Write-Host "`n=== Creating $Count Test Users ===" -ForegroundColor Cyan

    $domainDN = Get-DomainDN
    $userOUs = @(
        "OU=Employees,OU=Users,OU=$Prefix-Corporate,$domainDN"
        "OU=Contractors,OU=Users,OU=$Prefix-Corporate,$domainDN"
    )

    for ($i = 1; $i -le $Count; $i++) {
        $dept = Get-RandomElement $Config.Departments
        $title = Get-RandomElement $Config.Titles
        $ou = Get-RandomElement $userOUs

        $user = New-TestUser -Prefix $Prefix -Department $dept -Title $title -OUPath $ou
        if ($user) {
            $null = $State.users.Add($user)
        }

        if ($i % 25 -eq 0) {
            Write-Host "  ... Created $i/$Count users" -ForegroundColor Gray
        }
    }
}

#endregion

#region Group Creation Functions

function New-TestGroup {
    param(
        [string]$Name,
        [string]$OUPath,
        [ValidateSet('Security', 'Distribution')]
        [string]$GroupCategory = 'Security',
        [ValidateSet('Global', 'Universal', 'DomainLocal')]
        [string]$GroupScope = 'Global',
        [string]$Description
    )

    try {
        $existing = Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "  = Group exists: $Name" -ForegroundColor Gray
            return @{
                ObjectGUID = $existing.ObjectGUID.ToString()
                Name       = $Name
                DN         = $existing.DistinguishedName
            }
        }

        New-ADGroup -Name $Name -Path $OUPath -GroupCategory $GroupCategory -GroupScope $GroupScope -Description $Description
        $group = Get-ADGroup -Identity $Name -Properties ObjectGUID, DistinguishedName

        Write-Host "  + Group: $Name [$GroupScope/$GroupCategory]" -ForegroundColor Green
        return @{
            ObjectGUID     = $group.ObjectGUID.ToString()
            Name           = $Name
            DN             = $group.DistinguishedName
            GroupCategory  = $GroupCategory
            GroupScope     = $GroupScope
        }
    }
    catch {
        Write-Warning "  ! Failed to create group $Name`: $_"
        return $null
    }
}

function New-TestGroups {
    param(
        [string]$Prefix,
        [int]$Count,
        [hashtable]$State
    )

    Write-Host "`n=== Creating $Count Test Groups ===" -ForegroundColor Cyan

    $domainDN = Get-DomainDN
    $groupOU = "OU=Security,OU=Groups,OU=$Prefix-Corporate,$domainDN"

    # Create department groups
    foreach ($dept in $Config.Departments) {
        $group = New-TestGroup -Name "$Prefix-$dept" -OUPath $groupOU -Description "Department group for $dept"
        if ($group) {
            $null = $State.groups.Add($group)
        }
    }

    # Create role-based groups
    $roles = @('Readers', 'Writers', 'Admins', 'Managers', 'Operators', 'Auditors', 'Developers', 'DBAs')
    foreach ($role in $roles) {
        $group = New-TestGroup -Name "$Prefix-$role" -OUPath $groupOU -Description "Role group for $role"
        if ($group) {
            $null = $State.groups.Add($group)
        }
    }

    # Create additional random groups
    $remaining = $Count - $Config.Departments.Count - $roles.Count
    for ($i = 1; $i -le [Math]::Max(0, $remaining); $i++) {
        $id = (New-Guid).ToString().Substring(0, 8)
        $group = New-TestGroup -Name "$Prefix-Group-$id" -OUPath $groupOU -Description "Test group $i"
        if ($group) {
            $null = $State.groups.Add($group)
        }
    }
}

function New-NestedGroupChain {
    param(
        [string]$Prefix,
        [string]$ChainName,
        [int]$Depth,
        [string]$TargetGroup,
        [hashtable]$State
    )

    Write-Host "`n  Creating nested group chain: $ChainName (Depth: $Depth -> $TargetGroup)" -ForegroundColor Yellow

    $domainDN = Get-DomainDN
    $groupOU = "OU=Security,OU=Groups,OU=$Prefix-Corporate,$domainDN"

    $groups = @()
    $previousGroup = $null

    for ($i = 1; $i -le $Depth; $i++) {
        $groupName = "$Prefix-$ChainName-L$i"
        $group = New-TestGroup -Name $groupName -OUPath $groupOU -Description "Nested chain $ChainName level $i"

        if ($group) {
            $groups += $group
            $null = $State.groups.Add($group)

            # Add previous group as member (creates the chain)
            if ($previousGroup) {
                try {
                    Add-ADGroupMember -Identity $groupName -Members $previousGroup.Name
                    Write-Host "    + $($previousGroup.Name) -> $groupName" -ForegroundColor Gray
                }
                catch {
                    Write-Warning "    ! Failed to add $($previousGroup.Name) to $groupName`: $_"
                }
            }
            $previousGroup = $group
        }
    }

    # Add the final group to the target privileged group
    if ($previousGroup -and $TargetGroup) {
        try {
            Add-ADGroupMember -Identity $TargetGroup -Members $previousGroup.Name -ErrorAction Stop
            Write-Host "    + $($previousGroup.Name) -> $TargetGroup (TARGET)" -ForegroundColor Red
        }
        catch {
            Write-Warning "    ! Failed to add to target group (may require higher privileges): $_"
        }
    }

    return $groups
}

#endregion

#region Computer Creation Functions

function New-TestComputer {
    param(
        [string]$Name,
        [string]$OUPath,
        [switch]$UnconstrainedDelegation,
        [switch]$ConstrainedDelegation,
        [string[]]$AllowedToDelegateTo,
        [switch]$TrustedForDelegation
    )

    try {
        $existing = Get-ADComputer -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "  = Computer exists: $Name" -ForegroundColor Gray
            return @{
                ObjectGUID = $existing.ObjectGUID.ToString()
                Name       = $Name
                DN         = $existing.DistinguishedName
            }
        }

        New-ADComputer -Name $Name -Path $OUPath -Enabled $true
        $computer = Get-ADComputer -Identity $Name -Properties ObjectGUID, DistinguishedName

        # Configure delegation if requested
        if ($UnconstrainedDelegation) {
            Set-ADComputer -Identity $Name -TrustedForDelegation $true
            Write-Host "  + Computer (UNCONSTRAINED DELEGATION): $Name" -ForegroundColor Red
        }
        elseif ($ConstrainedDelegation -and $AllowedToDelegateTo) {
            Set-ADComputer -Identity $Name -TrustedForDelegation $false
            Set-ADComputer -Identity $Name -Add @{'msDS-AllowedToDelegateTo' = $AllowedToDelegateTo }
            Write-Host "  + Computer (CONSTRAINED DELEGATION): $Name -> $($AllowedToDelegateTo -join ', ')" -ForegroundColor Yellow
        }
        else {
            Write-Host "  + Computer: $Name" -ForegroundColor Green
        }

        return @{
            ObjectGUID              = $computer.ObjectGUID.ToString()
            Name                    = $Name
            DN                      = $computer.DistinguishedName
            UnconstrainedDelegation = $UnconstrainedDelegation.IsPresent
            ConstrainedDelegation   = $ConstrainedDelegation.IsPresent
            AllowedToDelegateTo     = $AllowedToDelegateTo
        }
    }
    catch {
        Write-Warning "  ! Failed to create computer $Name`: $_"
        return $null
    }
}

function New-TestComputers {
    param(
        [string]$Prefix,
        [int]$Count,
        [hashtable]$State
    )

    Write-Host "`n=== Creating $Count Test Computers ===" -ForegroundColor Cyan

    $domainDN = Get-DomainDN
    $workstationOU = "OU=Workstations,OU=Computers,OU=$Prefix-Corporate,$domainDN"
    $serverOU = "OU=Servers,OU=Computers,OU=$Prefix-Corporate,$domainDN"

    # Create workstations
    $workstationCount = [Math]::Floor($Count * 0.7)
    for ($i = 1; $i -le $workstationCount; $i++) {
        $name = "$Prefix-WKS-$('{0:D3}' -f $i)"
        $computer = New-TestComputer -Name $name -OUPath $workstationOU
        if ($computer) {
            $null = $State.computers.Add($computer)
        }
    }

    # Create servers
    $serverCount = $Count - $workstationCount
    for ($i = 1; $i -le $serverCount; $i++) {
        $name = "$Prefix-SRV-$('{0:D3}' -f $i)"
        $computer = New-TestComputer -Name $name -OUPath $serverOU
        if ($computer) {
            $null = $State.computers.Add($computer)
        }
    }
}

#endregion

#region Group Membership Functions

function Add-UsersToGroups {
    param(
        [hashtable]$State
    )

    Write-Host "`n=== Adding Users to Groups ===" -ForegroundColor Cyan

    $users = $State.users | Where-Object { -not $_.IsServiceAccount }
    $groups = $State.groups | Where-Object { $_.Name -notmatch '-L\d+$' }  # Exclude nested chain groups

    if ($users.Count -eq 0 -or $groups.Count -eq 0) {
        Write-Host "  No users or groups to process" -ForegroundColor Gray
        return
    }

    foreach ($user in $users) {
        # Add each user to 1-3 random groups
        $groupCount = Get-Random -Minimum 1 -Maximum 4
        $selectedGroups = $groups | Get-Random -Count ([Math]::Min($groupCount, $groups.Count))

        foreach ($group in $selectedGroups) {
            try {
                Add-ADGroupMember -Identity $group.Name -Members $user.SamAccountName -ErrorAction SilentlyContinue
            }
            catch {
                # Ignore - likely already a member
            }
        }
    }

    Write-Host "  Added users to random groups" -ForegroundColor Green
}

#endregion

#region Attack Path Creation Functions

function New-KerberoastableAccounts {
    param(
        [string]$Prefix,
        [int]$Count,
        [hashtable]$State
    )

    Write-Host "`n=== Creating Kerberoastable Service Accounts ===" -ForegroundColor Yellow

    $domainDN = Get-DomainDN
    $svcOU = "OU=ServiceAccounts,OU=Users,OU=$Prefix-Corporate,$domainDN"

    $services = @(
        @{ Name = 'SQL'; SPN = "MSSQLSvc/$Prefix-SQL01.$((Get-ADDomain).DNSRoot):1433" }
        @{ Name = 'HTTP'; SPN = "HTTP/$Prefix-WEB01.$((Get-ADDomain).DNSRoot)" }
        @{ Name = 'CIFS'; SPN = "CIFS/$Prefix-FILE01.$((Get-ADDomain).DNSRoot)" }
        @{ Name = 'LDAP'; SPN = "LDAP/$Prefix-DC01.$((Get-ADDomain).DNSRoot)" }
        @{ Name = 'WSMAN'; SPN = "WSMAN/$Prefix-MGT01.$((Get-ADDomain).DNSRoot)" }
    )

    foreach ($svc in ($services | Select-Object -First $Count)) {
        $user = New-TestUser -Prefix "svc_$Prefix" -Department 'IT' -Title 'Service Account' -OUPath $svcOU -ServiceAccount -SPN $svc.SPN
        if ($user) {
            $user.ServiceType = $svc.Name
            $null = $State.users.Add($user)
            $null = $State.attackPaths.Add(@{
                Type        = 'Kerberoastable'
                Principal   = $user.SamAccountName
                SPN         = $svc.SPN
                Description = "Service account with SPN - vulnerable to Kerberoasting"
            })
        }
    }
}

function New-ASREPRoastableAccounts {
    param(
        [string]$Prefix,
        [int]$Count,
        [hashtable]$State
    )

    Write-Host "`n=== Creating AS-REP Roastable Accounts ===" -ForegroundColor Yellow

    $domainDN = Get-DomainDN
    $userOU = "OU=Employees,OU=Users,OU=$Prefix-Corporate,$domainDN"

    for ($i = 1; $i -le $Count; $i++) {
        $user = New-TestUser -Prefix "$Prefix-NoPreAuth" -Department 'Legacy' -Title 'Legacy User' -OUPath $userOU -NoPreAuth
        if ($user) {
            $null = $State.users.Add($user)
            $null = $State.attackPaths.Add(@{
                Type        = 'ASREPRoastable'
                Principal   = $user.SamAccountName
                Description = "User with 'Do not require Kerberos preauthentication' enabled"
            })
        }
    }
}

function New-DelegationAttackPaths {
    param(
        [string]$Prefix,
        [hashtable]$State
    )

    Write-Host "`n=== Creating Delegation Attack Paths ===" -ForegroundColor Red

    $domainDN = Get-DomainDN
    $serverOU = "OU=Servers,OU=Computers,OU=$Prefix-Corporate,$domainDN"
    $dc = (Get-ADDomainController).HostName

    # 1. Unconstrained Delegation Computer
    $unconstrained = New-TestComputer -Name "$Prefix-DVWA01" -OUPath $serverOU -UnconstrainedDelegation
    if ($unconstrained) {
        $null = $State.computers.Add($unconstrained)
        $null = $State.attackPaths.Add(@{
            Type        = 'UnconstrainedDelegation'
            Principal   = $unconstrained.Name
            Description = "Computer trusted for delegation to ANY service - can impersonate any user"
        })
    }

    # 2. Constrained Delegation to DC (CIFS - allows DCSync-like access)
    $constrained = New-TestComputer -Name "$Prefix-DVWA02" -OUPath $serverOU -ConstrainedDelegation -AllowedToDelegateTo @("cifs/$dc", "ldap/$dc")
    if ($constrained) {
        $null = $State.computers.Add($constrained)
        $null = $State.attackPaths.Add(@{
            Type        = 'ConstrainedDelegation'
            Principal   = $constrained.Name
            Target      = $dc
            Services    = @("cifs/$dc", "ldap/$dc")
            Description = "Constrained delegation to DC - can access DC CIFS/LDAP as any user"
        })
    }

    # 3. Create a user with constrained delegation (Protocol Transition)
    $svcOU = "OU=ServiceAccounts,OU=Users,OU=$Prefix-Corporate,$domainDN"
    $svcUser = New-TestUser -Prefix "svc_$Prefix`_deleg" -Department 'IT' -Title 'Delegation Service' -OUPath $svcOU -ServiceAccount
    if ($svcUser) {
        try {
            # Enable protocol transition (T2A4D)
            Set-ADUser -Identity $svcUser.SamAccountName -TrustedForDelegation $false
            Set-ADAccountControl -Identity $svcUser.SamAccountName -TrustedToAuthForDelegation $true
            Set-ADUser -Identity $svcUser.SamAccountName -Add @{'msDS-AllowedToDelegateTo' = @("cifs/$dc") }

            $null = $State.users.Add($svcUser)
            $null = $State.attackPaths.Add(@{
                Type        = 'ConstrainedDelegationT2A4D'
                Principal   = $svcUser.SamAccountName
                Target      = $dc
                Description = "User with Protocol Transition + Constrained Delegation - can impersonate ANY user to DC"
            })
            Write-Host "  + Service Account (T2A4D DELEGATION): $($svcUser.SamAccountName) -> cifs/$dc" -ForegroundColor Red
        }
        catch {
            Write-Warning "  ! Failed to configure delegation for $($svcUser.SamAccountName): $_"
        }
    }
}

function New-ACLAttackPaths {
    param(
        [string]$Prefix,
        [hashtable]$State
    )

    Write-Host "`n=== Creating ACL-Based Attack Paths ===" -ForegroundColor Red

    $domainDN = Get-DomainDN

    # Get some test users and groups to grant permissions to
    $testUsers = $State.users | Where-Object { -not $_.IsServiceAccount } | Select-Object -First 10
    $testGroups = $State.groups | Where-Object { $_.Name -notmatch '-L\d+$' } | Select-Object -First 5

    if ($testUsers.Count -eq 0) {
        Write-Host "  No test users available for ACL attack paths" -ForegroundColor Gray
        return
    }

    # ACL attack scenarios
    $aclScenarios = @(
        @{
            Name       = 'GenericAll-User'
            Right      = 'GenericAll'
            TargetType = 'User'
            Description = 'Full control over another user - can reset password, modify attributes'
        }
        @{
            Name       = 'GenericWrite-User'
            Right      = 'GenericWrite'
            TargetType = 'User'
            Description = 'Can modify user attributes - write msDS-KeyCredentialLink for Shadow Credentials'
        }
        @{
            Name       = 'WriteDacl-User'
            Right      = 'WriteDacl'
            TargetType = 'User'
            Description = 'Can modify DACL - grant self GenericAll then takeover'
        }
        @{
            Name       = 'WriteOwner-Group'
            Right      = 'WriteOwner'
            TargetType = 'Group'
            Description = 'Can change group owner - then modify DACL and add self as member'
        }
        @{
            Name       = 'Self-Membership'
            Right      = 'Self'
            TargetType = 'Group'
            Description = 'Can add self to group'
        }
        @{
            Name       = 'ForceChangePassword'
            Right      = 'ExtendedRight'
            ExtendedRight = 'User-Force-Change-Password'
            TargetType = 'User'
            Description = 'Can reset user password without knowing current password'
        }
    )

    # Well-known extended right GUIDs
    $extendedRights = @{
        'User-Force-Change-Password' = '00299570-246d-11d0-a768-00aa006e0529'
        'DS-Replication-Get-Changes' = '1131f6aa-9c07-11d1-f79f-00c04fc2dcd2'
        'DS-Replication-Get-Changes-All' = '1131f6ad-9c07-11d1-f79f-00c04fc2dcd2'
    }

    $userIndex = 0
    foreach ($scenario in $aclScenarios) {
        if ($userIndex -ge $testUsers.Count) { break }

        $sourceUser = $testUsers[$userIndex]
        $targetUser = $testUsers[($userIndex + 1) % $testUsers.Count]
        $targetGroup = if ($testGroups.Count -gt 0) { $testGroups[$userIndex % $testGroups.Count] } else { $null }

        try {
            $target = if ($scenario.TargetType -eq 'User') {
                Get-ADUser -Identity $targetUser.SamAccountName
            }
            else {
                if ($targetGroup) { Get-ADGroup -Identity $targetGroup.Name } else { $null }
            }

            if (-not $target) {
                $userIndex++
                continue
            }

            $sourceIdentity = Get-ADUser -Identity $sourceUser.SamAccountName
            $targetPath = "AD:\$($target.DistinguishedName)"

            $acl = Get-Acl -Path $targetPath

            # Build the ACE based on scenario
            $ace = switch ($scenario.Right) {
                'GenericAll' {
                    New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                        $sourceIdentity.SID,
                        [System.DirectoryServices.ActiveDirectoryRights]::GenericAll,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )
                }
                'GenericWrite' {
                    New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                        $sourceIdentity.SID,
                        [System.DirectoryServices.ActiveDirectoryRights]::GenericWrite,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )
                }
                'WriteDacl' {
                    New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                        $sourceIdentity.SID,
                        [System.DirectoryServices.ActiveDirectoryRights]::WriteDacl,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )
                }
                'WriteOwner' {
                    New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                        $sourceIdentity.SID,
                        [System.DirectoryServices.ActiveDirectoryRights]::WriteOwner,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )
                }
                'Self' {
                    New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                        $sourceIdentity.SID,
                        [System.DirectoryServices.ActiveDirectoryRights]::Self,
                        [System.Security.AccessControl.AccessControlType]::Allow,
                        [guid]'bf9679c0-0de6-11d0-a285-00aa003049e2'  # Member attribute
                    )
                }
                'ExtendedRight' {
                    $rightGuid = $extendedRights[$scenario.ExtendedRight]
                    New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                        $sourceIdentity.SID,
                        [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
                        [System.Security.AccessControl.AccessControlType]::Allow,
                        [guid]$rightGuid
                    )
                }
            }

            if ($ace) {
                $acl.AddAccessRule($ace)
                Set-Acl -Path $targetPath -AclObject $acl

                Write-Host "  + ACL: $($sourceUser.SamAccountName) --[$($scenario.Right)]--> $($target.Name)" -ForegroundColor Yellow

                $null = $State.aclChanges.Add(@{
                    Source      = $sourceUser.SamAccountName
                    SourceDN    = $sourceUser.DN
                    Target      = $target.Name
                    TargetDN    = $target.DistinguishedName
                    Right       = $scenario.Right
                    Description = $scenario.Description
                })

                $null = $State.attackPaths.Add(@{
                    Type        = "ACL-$($scenario.Right)"
                    Source      = $sourceUser.SamAccountName
                    Target      = $target.Name
                    Right       = $scenario.Right
                    Description = $scenario.Description
                })
            }
        }
        catch {
            Write-Warning "  ! Failed to create ACL attack path ($($scenario.Name)): $_"
        }

        $userIndex++
    }
}

function New-NestedGroupAttackPaths {
    param(
        [string]$Prefix,
        [hashtable]$State
    )

    Write-Host "`n=== Creating Nested Group Attack Paths ===" -ForegroundColor Red

    # Create chains to various privileged groups
    $chains = @(
        @{ Name = 'DA-Chain'; Target = 'Domain Admins'; Depth = 5 }
        @{ Name = 'BA-Chain'; Target = 'Administrators'; Depth = 4 }
        @{ Name = 'AO-Chain'; Target = 'Account Operators'; Depth = 3 }
        @{ Name = 'BO-Chain'; Target = 'Backup Operators'; Depth = 3 }
    )

    foreach ($chain in $chains) {
        try {
            # Verify target group exists
            $targetGroup = Get-ADGroup -Identity $chain.Target -ErrorAction Stop

            $groups = New-NestedGroupChain -Prefix $Prefix -ChainName $chain.Name -Depth $chain.Depth -TargetGroup $chain.Target -State $State

            if ($groups.Count -gt 0) {
                # Add a test user to the start of the chain
                $testUsers = $State.users | Where-Object { -not $_.IsServiceAccount }
                if ($testUsers.Count -gt 0) {
                    $chainUser = $testUsers | Get-Random
                    try {
                        Add-ADGroupMember -Identity $groups[0].Name -Members $chainUser.SamAccountName
                        Write-Host "    + User $($chainUser.SamAccountName) added to chain start ($($groups[0].Name))" -ForegroundColor Cyan

                        $null = $State.attackPaths.Add(@{
                            Type        = 'NestedGroupChain'
                            Source      = $chainUser.SamAccountName
                            Target      = $chain.Target
                            ChainLength = $chain.Depth
                            Path        = @($chainUser.SamAccountName) + ($groups | ForEach-Object { $_.Name }) + @($chain.Target)
                            Description = "User is $($chain.Depth + 1) hops from $($chain.Target) via nested groups"
                        })
                    }
                    catch {
                        Write-Warning "    ! Failed to add user to chain: $_"
                    }
                }
            }
        }
        catch {
            Write-Warning "  ! Failed to create chain to $($chain.Target): $_"
        }
    }
}

function New-RBCDAttackPath {
    param(
        [string]$Prefix,
        [hashtable]$State
    )

    Write-Host "`n=== Creating Resource-Based Constrained Delegation (RBCD) Attack Path ===" -ForegroundColor Red

    $domainDN = Get-DomainDN
    $serverOU = "OU=Servers,OU=Computers,OU=$Prefix-Corporate,$domainDN"

    # Create a "victim" server that trusts another computer for delegation
    $victimServer = New-TestComputer -Name "$Prefix-DVWA03" -OUPath $serverOU

    # Create an "attacker" computer that will be trusted
    $attackerComputer = New-TestComputer -Name "$Prefix-DVWA04" -OUPath $serverOU

    if ($victimServer -and $attackerComputer) {
        try {
            # Get the attacker computer's SID
            $attackerObj = Get-ADComputer -Identity $attackerComputer.Name

            # Create security descriptor allowing the attacker computer to delegate
            $sd = New-Object Security.AccessControl.RawSecurityDescriptor("O:BAD:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;$($attackerObj.SID))")
            $sdBytes = New-Object byte[] $sd.BinaryLength
            $sd.GetBinaryForm($sdBytes, 0)

            # Set RBCD on victim server
            Set-ADComputer -Identity $victimServer.Name -Add @{'msDS-AllowedToActOnBehalfOfOtherIdentity' = $sdBytes }

            Write-Host "  + RBCD: $($attackerComputer.Name) can delegate to $($victimServer.Name)" -ForegroundColor Red

            $null = $State.computers.Add($victimServer)
            $null = $State.computers.Add($attackerComputer)
            $null = $State.attackPaths.Add(@{
                Type        = 'RBCD'
                Attacker    = $attackerComputer.Name
                Victim      = $victimServer.Name
                Description = "Resource-Based Constrained Delegation - attacker computer can impersonate users to victim server"
            })
        }
        catch {
            Write-Warning "  ! Failed to configure RBCD: $_"
        }
    }
}

function New-ShadowCredentialsAttackPath {
    param(
        [string]$Prefix,
        [hashtable]$State
    )

    Write-Host "`n=== Creating Shadow Credentials Attack Path ===" -ForegroundColor Red

    # Find a test user to be the "attacker" (one who can write to another user's msDS-KeyCredentialLink)
    $attackers = $State.users | Where-Object { -not $_.IsServiceAccount } | Select-Object -First 2

    if ($attackers.Count -lt 2) {
        Write-Host "  Need at least 2 test users for Shadow Credentials attack path" -ForegroundColor Gray
        return
    }

    $attacker = $attackers[0]
    $victim = $attackers[1]

    try {
        $attackerObj = Get-ADUser -Identity $attacker.SamAccountName
        $victimObj = Get-ADUser -Identity $victim.SamAccountName

        $targetPath = "AD:\$($victimObj.DistinguishedName)"
        $acl = Get-Acl -Path $targetPath

        # Grant write access to msDS-KeyCredentialLink (GUID: 5b47d60f-6090-40b2-9f37-2a4de88f3063)
        $keyCredLinkGuid = [guid]'5b47d60f-6090-40b2-9f37-2a4de88f3063'
        $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $attackerObj.SID,
            [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty,
            [System.Security.AccessControl.AccessControlType]::Allow,
            $keyCredLinkGuid
        )

        $acl.AddAccessRule($ace)
        Set-Acl -Path $targetPath -AclObject $acl

        Write-Host "  + Shadow Creds: $($attacker.SamAccountName) can write msDS-KeyCredentialLink on $($victim.SamAccountName)" -ForegroundColor Red

        $null = $State.aclChanges.Add(@{
            Source      = $attacker.SamAccountName
            Target      = $victim.SamAccountName
            Right       = 'WriteProperty-msDS-KeyCredentialLink'
            Description = 'Can write Shadow Credentials - obtain TGT as victim without password'
        })

        $null = $State.attackPaths.Add(@{
            Type        = 'ShadowCredentials'
            Source      = $attacker.SamAccountName
            Target      = $victim.SamAccountName
            Description = 'Can write msDS-KeyCredentialLink - allows obtaining TGT as victim via certificate'
        })
    }
    catch {
        Write-Warning "  ! Failed to create Shadow Credentials attack path: $_"
    }
}

function New-GPOAttackPath {
    param(
        [string]$Prefix,
        [hashtable]$State
    )

    Write-Host "`n=== Creating GPO Attack Path ===" -ForegroundColor Red

    try {
        # Check if GroupPolicy module is available
        if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
            Write-Host "  GroupPolicy module not available - skipping GPO attack paths" -ForegroundColor Gray
            return
        }

        Import-Module GroupPolicy -ErrorAction Stop

        # Create a test GPO
        $gpoName = "$Prefix-TestGPO"
        $gpo = New-GPO -Name $gpoName -Comment "Alpenglow test GPO for attack path testing" -ErrorAction SilentlyContinue

        if (-not $gpo) {
            $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
        }

        if ($gpo) {
            Write-Host "  + GPO Created: $gpoName" -ForegroundColor Green

            # Grant a test user edit access to the GPO
            $testUsers = $State.users | Where-Object { -not $_.IsServiceAccount } | Select-Object -First 1
            if ($testUsers) {
                try {
                    # This grants the user ability to edit the GPO
                    $domainName = (Get-ADDomain).NetBIOSName
                    Set-GPPermission -Name $gpoName -TargetName "$domainName\$($testUsers.SamAccountName)" -TargetType User -PermissionLevel GpoEdit

                    Write-Host "  + GPO Edit Access: $($testUsers.SamAccountName) can edit $gpoName" -ForegroundColor Yellow

                    $null = $State.gpos.Add(@{
                        Name     = $gpoName
                        GpoId    = $gpo.Id.ToString()
                        EditUser = $testUsers.SamAccountName
                    })

                    $null = $State.attackPaths.Add(@{
                        Type        = 'GPOEdit'
                        Source      = $testUsers.SamAccountName
                        Target      = $gpoName
                        Description = 'User can edit GPO - can deploy malicious scripts/settings to linked OUs'
                    })
                }
                catch {
                    Write-Warning "  ! Failed to set GPO permissions: $_"
                }
            }
        }
    }
    catch {
        Write-Warning "  ! Failed to create GPO attack path: $_"
    }
}

function New-DCReplicationRightsAttackPath {
    param(
        [string]$Prefix,
        [hashtable]$State
    )

    Write-Host "`n=== Creating DCSync Rights Attack Path ===" -ForegroundColor Red
    Write-Host "  (Granting replication rights to a test user - THIS IS DANGEROUS)" -ForegroundColor Yellow

    # Get a test service account to grant DCSync rights
    $svcAccounts = $State.users | Where-Object { $_.IsServiceAccount } | Select-Object -First 1

    if (-not $svcAccounts) {
        Write-Host "  No service accounts available - skipping DCSync attack path" -ForegroundColor Gray
        return
    }

    try {
        $domainDN = Get-DomainDN
        $svcUser = Get-ADUser -Identity $svcAccounts.SamAccountName

        # Extended rights for DCSync
        $replicationRights = @(
            [guid]'1131f6aa-9c07-11d1-f79f-00c04fc2dcd2'  # DS-Replication-Get-Changes
            [guid]'1131f6ad-9c07-11d1-f79f-00c04fc2dcd2'  # DS-Replication-Get-Changes-All
        )

        $targetPath = "AD:\$domainDN"
        $acl = Get-Acl -Path $targetPath

        foreach ($rightGuid in $replicationRights) {
            $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                $svcUser.SID,
                [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
                [System.Security.AccessControl.AccessControlType]::Allow,
                $rightGuid
            )
            $acl.AddAccessRule($ace)
        }

        Set-Acl -Path $targetPath -AclObject $acl

        Write-Host "  + DCSync Rights: $($svcAccounts.SamAccountName) has replication rights on domain!" -ForegroundColor Red

        $null = $State.aclChanges.Add(@{
            Source      = $svcAccounts.SamAccountName
            Target      = $domainDN
            Right       = 'DS-Replication-Get-Changes + DS-Replication-Get-Changes-All'
            Description = 'Can perform DCSync attack to extract all password hashes'
        })

        $null = $State.attackPaths.Add(@{
            Type        = 'DCSync'
            Source      = $svcAccounts.SamAccountName
            Target      = 'Domain'
            Description = 'User has DCSync rights - can extract all domain password hashes via replication'
        })
    }
    catch {
        Write-Warning "  ! Failed to create DCSync attack path: $_"
    }
}

#endregion

#region Main Functions

function Invoke-CreateBaseData {
    param(
        [string]$Prefix,
        [hashtable]$State,
        [hashtable]$Config
    )

    Write-Host "`n" + "=" * 60 -ForegroundColor White
    Write-Host " CREATING BASE TEST DATA" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor White

    # Create OU structure
    New-TestOUStructure -Prefix $Prefix -State $State

    # Create users
    New-TestUsers -Prefix $Prefix -Count $Config.UserCount -State $State

    # Create groups
    New-TestGroups -Prefix $Prefix -Count $Config.GroupCount -State $State

    # Create computers
    New-TestComputers -Prefix $Prefix -Count $Config.ComputerCount -State $State

    # Add users to groups
    Add-UsersToGroups -State $State

    Save-State $State

    Write-Host "`n" + "=" * 60 -ForegroundColor White
    Write-Host " BASE DATA CREATION COMPLETE" -ForegroundColor Green
    Write-Host "=" * 60 -ForegroundColor White
    Write-Host "  Users: $($State.users.Count)" -ForegroundColor Gray
    Write-Host "  Groups: $($State.groups.Count)" -ForegroundColor Gray
    Write-Host "  Computers: $($State.computers.Count)" -ForegroundColor Gray
    Write-Host "  OUs: $($State.ous.Count)" -ForegroundColor Gray
}

function Invoke-CreateAttackPaths {
    param(
        [string]$Prefix,
        [hashtable]$State
    )

    Write-Host "`n" + "=" * 60 -ForegroundColor Red
    Write-Host " CREATING ATTACK PATHS (MISCONFIGURATIONS)" -ForegroundColor Red
    Write-Host "=" * 60 -ForegroundColor Red
    Write-Host "`nWARNING: This creates intentional security misconfigurations!" -ForegroundColor Yellow
    Write-Host "Only run this in a test/lab environment." -ForegroundColor Yellow

    # Kerberoastable accounts
    New-KerberoastableAccounts -Prefix $Prefix -Count 5 -State $State

    # AS-REP roastable accounts
    New-ASREPRoastableAccounts -Prefix $Prefix -Count 3 -State $State

    # Delegation attack paths
    New-DelegationAttackPaths -Prefix $Prefix -State $State

    # RBCD attack path
    New-RBCDAttackPath -Prefix $Prefix -State $State

    # ACL-based attack paths
    New-ACLAttackPaths -Prefix $Prefix -State $State

    # Nested group attack paths
    New-NestedGroupAttackPaths -Prefix $Prefix -State $State

    # Shadow Credentials attack path
    New-ShadowCredentialsAttackPath -Prefix $Prefix -State $State

    # GPO attack path
    New-GPOAttackPath -Prefix $Prefix -State $State

    # DCSync attack path (very dangerous - creates actual DCSync rights)
    # Uncomment only if you really want this in your lab
    # New-DCReplicationRightsAttackPath -Prefix $Prefix -State $State

    Save-State $State

    Write-Host "`n" + "=" * 60 -ForegroundColor Red
    Write-Host " ATTACK PATH CREATION COMPLETE" -ForegroundColor Red
    Write-Host "=" * 60 -ForegroundColor Red

    Write-Host "`nAttack Paths Created:" -ForegroundColor Yellow
    $State.attackPaths | Group-Object Type | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Gray
    }

    Write-Host "`nNext Steps:" -ForegroundColor Cyan
    Write-Host "  1. Run BloodHound collector: SharpHound.exe -c All" -ForegroundColor Gray
    Write-Host "  2. Import data into BloodHound/Alpenglow" -ForegroundColor Gray
    Write-Host "  3. Analyze attack paths" -ForegroundColor Gray
}

function Invoke-Cleanup {
    param(
        [string]$Prefix,
        [hashtable]$State
    )

    Write-Host "`n" + "=" * 60 -ForegroundColor Yellow
    Write-Host " CLEANING UP TEST DATA" -ForegroundColor Yellow
    Write-Host "=" * 60 -ForegroundColor Yellow

    $deleted = @{ users = 0; groups = 0; computers = 0; ous = 0; gpos = 0 }

    # Delete GPOs first
    if ($State.gpos.Count -gt 0) {
        Write-Host "`nDeleting GPOs..." -ForegroundColor White
        foreach ($gpo in $State.gpos) {
            try {
                Remove-GPO -Name $gpo.Name -ErrorAction Stop
                Write-Host "  - GPO: $($gpo.Name)" -ForegroundColor Gray
                $deleted.gpos++
            }
            catch {
                Write-Warning "  ! Failed to delete GPO $($gpo.Name): $_"
            }
        }
    }

    # Delete computers
    Write-Host "`nDeleting computers..." -ForegroundColor White
    foreach ($computer in $State.computers) {
        try {
            Remove-ADComputer -Identity $computer.Name -Confirm:$false -ErrorAction Stop
            Write-Host "  - Computer: $($computer.Name)" -ForegroundColor Gray
            $deleted.computers++
        }
        catch {
            Write-Warning "  ! Failed to delete computer $($computer.Name): $_"
        }
    }

    # Delete users
    Write-Host "`nDeleting users..." -ForegroundColor White
    foreach ($user in $State.users) {
        try {
            Remove-ADUser -Identity $user.SamAccountName -Confirm:$false -ErrorAction Stop
            Write-Host "  - User: $($user.SamAccountName)" -ForegroundColor Gray
            $deleted.users++
        }
        catch {
            Write-Warning "  ! Failed to delete user $($user.SamAccountName): $_"
        }
    }

    # Delete groups (reverse order to handle nested groups)
    Write-Host "`nDeleting groups..." -ForegroundColor White
    $groupsReversed = $State.groups | Sort-Object { $_.Name } -Descending
    foreach ($group in $groupsReversed) {
        try {
            Remove-ADGroup -Identity $group.Name -Confirm:$false -ErrorAction Stop
            Write-Host "  - Group: $($group.Name)" -ForegroundColor Gray
            $deleted.groups++
        }
        catch {
            Write-Warning "  ! Failed to delete group $($group.Name): $_"
        }
    }

    # Delete OUs (reverse order - children first)
    Write-Host "`nDeleting OUs..." -ForegroundColor White
    $ousReversed = $State.ous | Sort-Object { $_.DN.Length } -Descending
    foreach ($ou in $ousReversed) {
        try {
            Set-ADOrganizationalUnit -Identity $ou.DN -ProtectedFromAccidentalDeletion $false -ErrorAction SilentlyContinue
            Remove-ADOrganizationalUnit -Identity $ou.DN -Confirm:$false -ErrorAction Stop
            Write-Host "  - OU: $($ou.Name)" -ForegroundColor Gray
            $deleted.ous++
        }
        catch {
            Write-Warning "  ! Failed to delete OU $($ou.Name): $_"
        }
    }

    # Clear state
    $State.users.Clear()
    $State.groups.Clear()
    $State.computers.Clear()
    $State.ous.Clear()
    $State.gpos.Clear()
    $State.aclChanges.Clear()
    $State.attackPaths.Clear()
    Save-State $State

    Write-Host "`n" + "=" * 60 -ForegroundColor Green
    Write-Host " CLEANUP COMPLETE" -ForegroundColor Green
    Write-Host "=" * 60 -ForegroundColor Green
    Write-Host "  Users: $($deleted.users)" -ForegroundColor Gray
    Write-Host "  Groups: $($deleted.groups)" -ForegroundColor Gray
    Write-Host "  Computers: $($deleted.computers)" -ForegroundColor Gray
    Write-Host "  OUs: $($deleted.ous)" -ForegroundColor Gray
    Write-Host "  GPOs: $($deleted.gpos)" -ForegroundColor Gray
}

function Show-Status {
    param([hashtable]$State)

    Write-Host "`n" + "=" * 60 -ForegroundColor Cyan
    Write-Host " CURRENT TEST DATA STATUS" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan

    Write-Host "`nObjects Created:" -ForegroundColor White
    Write-Host "  Users:     $($State.users.Count)" -ForegroundColor Gray
    Write-Host "  Groups:    $($State.groups.Count)" -ForegroundColor Gray
    Write-Host "  Computers: $($State.computers.Count)" -ForegroundColor Gray
    Write-Host "  OUs:       $($State.ous.Count)" -ForegroundColor Gray
    Write-Host "  GPOs:      $($State.gpos.Count)" -ForegroundColor Gray

    Write-Host "`nAttack Paths:" -ForegroundColor Red
    if ($State.attackPaths.Count -eq 0) {
        Write-Host "  (none created)" -ForegroundColor Gray
    }
    else {
        $State.attackPaths | Group-Object Type | ForEach-Object {
            Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Yellow
        }
    }

    Write-Host "`nACL Changes:" -ForegroundColor Yellow
    if ($State.aclChanges.Count -eq 0) {
        Write-Host "  (none created)" -ForegroundColor Gray
    }
    else {
        foreach ($acl in $State.aclChanges) {
            Write-Host "  $($acl.Source) --[$($acl.Right)]--> $($acl.Target)" -ForegroundColor Gray
        }
    }
}

function Show-Menu {
    param([hashtable]$State)

    Write-Host "`n" + "=" * 60 -ForegroundColor White
    Write-Host " ACTIVE DIRECTORY TEST DATA GENERATOR" -ForegroundColor Cyan
    Write-Host " For Alpenglow Security Posture Analysis" -ForegroundColor Gray
    Write-Host "=" * 60 -ForegroundColor White

    if ($State.users.Count -gt 0 -or $State.groups.Count -gt 0) {
        Write-Host "`nExisting Data:" -ForegroundColor Yellow
        Write-Host "  $($State.users.Count) users, $($State.groups.Count) groups, $($State.computers.Count) computers" -ForegroundColor Gray
        Write-Host "  $($State.attackPaths.Count) attack paths configured" -ForegroundColor Red
    }

    Write-Host "`nOptions:" -ForegroundColor White
    Write-Host "  [1] Create base test data (users, groups, computers, OUs)" -ForegroundColor Green
    Write-Host "  [2] Create attack paths (misconfigurations)" -ForegroundColor Red
    Write-Host "  [3] Show current status" -ForegroundColor Cyan
    Write-Host "  [4] Cleanup all test data" -ForegroundColor Yellow
    Write-Host "  [Q] Quit" -ForegroundColor Gray

    return (Read-Host "`nSelect option")
}

#endregion

#region Main Execution

# Verify AD module is available
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "ActiveDirectory PowerShell module is required. Install RSAT or run on a domain controller."
    exit 1
}

Import-Module ActiveDirectory -ErrorAction Stop

# Verify domain connectivity
try {
    $domain = Get-ADDomain -ErrorAction Stop
    Write-Host "Connected to domain: $($domain.DNSRoot)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Active Directory: $_"
    exit 1
}

$State = Get-State

# Non-interactive mode
if ($NonInteractive -and $Action) {
    switch ($Action) {
        'Create' { Invoke-CreateBaseData -Prefix $TestPrefix -State $State -Config $Config }
        'AttackPaths' { Invoke-CreateAttackPaths -Prefix $TestPrefix -State $State }
        'Cleanup' { Invoke-Cleanup -Prefix $TestPrefix -State $State }
        'Status' { Show-Status -State $State }
    }
    exit 0
}

# Interactive menu
while ($true) {
    $choice = Show-Menu -State $State

    switch ($choice) {
        '1' { Invoke-CreateBaseData -Prefix $TestPrefix -State $State -Config $Config }
        '2' { Invoke-CreateAttackPaths -Prefix $TestPrefix -State $State }
        '3' { Show-Status -State $State }
        '4' { Invoke-Cleanup -Prefix $TestPrefix -State $State }
        'Q' { exit 0 }
        'q' { exit 0 }
        default { Write-Host "Invalid option" -ForegroundColor Red }
    }
}

#endregion
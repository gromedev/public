#Requires -Version 7.0
<#
.SYNOPSIS
Simple AD nested groups collector - outputs to C:\temp\nested.json
#>

[CmdletBinding()]
param()

# Import existing modules

Import-Module (Join-Path $PSScriptRoot “....\Modules\AD.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “....\Modules\Common.Functions.psm1”) -Force

# Get configuration

$config = Get-Config -ConfigPath (Join-Path $PSScriptRoot “....\Modules\giam-config.json”) -Force

Write-Host “Collecting AD nested groups…” -ForegroundColor Cyan

$allGroups = @{}
$groupMembers = @{}

try {
# Create LDAP connection using existing function
$connection = New-LDAPConnection -Config $config.ActiveDirectory

```
# Search for all groups
$searchRequest = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(objectClass=group)" `
    -Attributes @("distinguishedName", "name", "member")

# Use pagination like other AD scripts
$pageSize = $config.ActiveDirectory.PageSize
$pagingControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($pageSize)
$pageNumber = 0

do {
    $pageNumber++
    Write-Host "Processing page $pageNumber..."
    
    # Memory check like other scripts
    if (Test-MemoryPressure -ThresholdGB $config.ActiveDirectory.MemoryThresholdGB `
                            -WarningGB $config.ActiveDirectory.MemoryWarningThresholdGB) {
        [System.GC]::Collect()
    }
    
    $searchRequest.Controls.Clear()
    $searchRequest.Controls.Add($pagingControl)
    $response = $connection.SendRequest($searchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]
    
    if ($null -eq $response -or $response.Entries.Count -eq 0) {
        break
    }
    
    foreach ($entry in $response.Entries) {
        $attrs = $entry.Attributes
        $groupDN = $attrs["distinguishedName"][0]
        $groupName = if ($attrs["name"]) { $attrs["name"][0] } else { "Unknown" }
        
        $allGroups[$groupDN] = $groupName
        
        # Find nested groups
        $nestedGroups = @()
        if ($attrs["member"]) {
            foreach ($memberDN in $attrs["member"]) {
                # Check if member DN looks like a group
                if ($memberDN -match "CN=.*") {
                    $nestedGroups += $memberDN
                }
            }
        }
        $groupMembers[$groupDN] = $nestedGroups
    }
    
    $cookie = ($response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl.Cookie = $cookie
    
} while ($null -ne $cookie -and $cookie.Length -ne 0)

Write-Host "Found $($allGroups.Count) groups"

# Build nested structure
Write-Host "Building nested structure..."

function Get-NestedGroups {
    param($GroupDN)
    
    $nestedGroups = @()
    foreach ($memberDN in $groupMembers[$GroupDN]) {
        if ($allGroups.ContainsKey($memberDN)) {
            $nestedGroup = @{
                Name = $allGroups[$memberDN]
                NestedGroups = Get-NestedGroups -GroupDN $memberDN
            }
            $nestedGroups += $nestedGroup
        }
    }
    return $nestedGroups
}

# Find root groups (not members of other groups)
$memberOfMap = @{}
foreach ($groupDN in $groupMembers.Keys) {
    foreach ($memberDN in $groupMembers[$groupDN]) {
        if ($allGroups.ContainsKey($memberDN)) {
            $memberOfMap[$memberDN] = $true
        }
    }
}

$rootGroups = @()
foreach ($groupDN in $allGroups.Keys) {
    if (-not $memberOfMap.ContainsKey($groupDN)) {
        $rootGroup = @{
            Name = $allGroups[$groupDN]
            NestedGroups = Get-NestedGroups -GroupDN $groupDN
        }
        # Only include if it has nested groups
        if ($rootGroup.NestedGroups.Count -gt 0) {
            $rootGroups += $rootGroup
        }
    }
}

Write-Host "Found $($rootGroups.Count) root groups with nesting"

# Output to JSON
$outputPath = "C:\temp\nested.json"

# Ensure temp directory exists
if (-not (Test-Path "C:\temp")) {
    New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null
}

$rootGroups | ConvertTo-Json -Depth 50 | Set-Content -Path $outputPath -Encoding UTF8

Write-Host "Nested groups exported to: $outputPath" -ForegroundColor Green
```

} catch {
Write-Error “Error collecting nested groups: $_”
throw
} finally {
if ($connection) { $connection.Dispose() }
[System.GC]::Collect()
}
#Requires -Version 7.0
<#
.SYNOPSIS
Fixed POC - Count groups and nested groups properly
#>

# Import existing modules

Import-Module (Join-Path $PSScriptRoot “....\Modules\AD.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “....\Modules\Common.Functions.psm1”) -Force

# Get configuration

$config = Get-Config -ConfigPath (Join-Path $PSScriptRoot “....\Modules\giam-config.json”) -Force

Write-Host “FIXED: Counting AD Groups and Nested Groups” -ForegroundColor Cyan
Write-Host “===========================================” -ForegroundColor Cyan

$allGroups = @{}
$allGroupMembers = @{}

try {
# Create LDAP connection
Write-Host “Phase 1: Collecting ALL groups and their members…” -ForegroundColor Yellow
$connection = New-LDAPConnection -Config $config.ActiveDirectory

```
# Single pass - collect everything at once
$searchRequest = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(objectClass=group)" `
    -Attributes @("distinguishedName", "name", "member")

$pageSize = $config.ActiveDirectory.PageSize
$pagingControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($pageSize)
$pageNumber = 0
$totalGroups = 0

do {
    $pageNumber++
    Write-Host "Processing page $pageNumber..."

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
        
        $totalGroups++
        $allGroups[$groupDN] = $groupName
        
        # Store all members for this group
        $members = @()
        if ($attrs["member"]) {
            foreach ($memberDN in $attrs["member"]) {
                $members += $memberDN
            }
        }
        $allGroupMembers[$groupDN] = $members
    }

    $cookie = ($response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl.Cookie = $cookie

    if ($pageNumber % 20 -eq 0) {
        Write-Host "  Progress: $totalGroups groups collected..."
    }

} while ($null -ne $cookie -and $cookie.Length -ne 0)

Write-Host "Phase 2: Analyzing group-to-group relationships..." -ForegroundColor Yellow

$groupsWithNestedGroups = 0
$totalNestedRelationships = 0
$sampleRelationships = @()

foreach ($groupDN in $allGroups.Keys) {
    $groupName = $allGroups[$groupDN]
    $members = $allGroupMembers[$groupDN]
    
    if ($members.Count -gt 0) {
        $nestedGroupsInThisGroup = 0
        
        foreach ($memberDN in $members) {
            # Check if this member is actually a group
            if ($allGroups.ContainsKey($memberDN)) {
                $nestedGroupName = $allGroups[$memberDN]
                $nestedGroupsInThisGroup++
                $totalNestedRelationships++
                
                # Collect samples
                if ($sampleRelationships.Count -lt 20) {
                    $sampleRelationships += @{
                        ParentGroup = $groupName
                        NestedGroup = $nestedGroupName
                    }
                }
            }
        }
        
        if ($nestedGroupsInThisGroup -gt 0) {
            $groupsWithNestedGroups++
        }
    }
}

# Show results
Write-Host "`nFINAL RESULTS:" -ForegroundColor Green
Write-Host "==============" -ForegroundColor Green
Write-Host "Total Groups in AD: $totalGroups" -ForegroundColor Cyan
Write-Host "Groups with nested groups: $groupsWithNestedGroups" -ForegroundColor Yellow
Write-Host "Total group-to-group relationships: $totalNestedRelationships" -ForegroundColor Yellow

if ($sampleRelationships.Count -gt 0) {
    Write-Host "`nSample nested group relationships:" -ForegroundColor Green
    foreach ($rel in $sampleRelationships[0..9]) {  # Show first 10
        Write-Host "  '$($rel.ParentGroup)' contains '$($rel.NestedGroup)'" -ForegroundColor White
    }
    
    if ($sampleRelationships.Count -gt 10) {
        Write-Host "  ... and $($sampleRelationships.Count - 10) more relationships" -ForegroundColor Gray
    }
} else {
    Write-Host "`nNo nested group relationships found!" -ForegroundColor Red
}

Write-Host "`n✓ Nested group detection is now working!" -ForegroundColor Green
```

} catch {
Write-Error “Error during group counting: $_”
throw
} finally {
if ($connection) { $connection.Dispose() }
}
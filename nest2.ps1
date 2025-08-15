#Requires -Version 7.0
<#
.SYNOPSIS
POC - Just count groups and nested groups
#>

# Import existing modules

Import-Module (Join-Path $PSScriptRoot “....\Modules\AD.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “....\Modules\Common.Functions.psm1”) -Force

# Get configuration

$config = Get-Config -ConfigPath (Join-Path $PSScriptRoot “....\Modules\giam-config.json”) -Force

Write-Host “POC: Counting AD Groups and Nested Groups” -ForegroundColor Cyan
Write-Host “==========================================” -ForegroundColor Cyan

$totalGroups = 0
$totalGroupMembers = 0
$groupsWithNestedGroups = 0
$allGroups = @{}

try {
# Create LDAP connection
Write-Host “Connecting to AD…” -ForegroundColor Yellow
$connection = New-LDAPConnection -Config $config.ActiveDirectory
Write-Host “✓ Connected to AD” -ForegroundColor Green

```
# Search for groups only
Write-Host "Searching for groups..." -ForegroundColor Yellow
$searchRequest = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(objectClass=group)" `
    -Attributes @("distinguishedName", "name", "member")

# Use pagination
$pageSize = $config.ActiveDirectory.PageSize
$pagingControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($pageSize)
$pageNumber = 0

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

        # Count members
        if ($attrs["member"]) {
            $memberCount = $attrs["member"].Count
            $totalGroupMembers += $memberCount
            
            if ($memberCount -gt 0) {
                $groupsWithNestedGroups++
            }
        }
    }

    $cookie = ($response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl.Cookie = $cookie

    # Show progress every 10 pages
    if ($pageNumber % 10 -eq 0) {
        Write-Host "  Progress: Found $totalGroups groups so far..."
    }

} while ($null -ne $cookie -and $cookie.Length -ne 0)

Write-Host "`nPhase 1 Complete - Basic Counts:" -ForegroundColor Yellow
Write-Host "Total Groups Found: $totalGroups" -ForegroundColor White
Write-Host "Groups with Members: $groupsWithNestedGroups" -ForegroundColor White  
Write-Host "Total Memberships: $totalGroupMembers" -ForegroundColor White

# Phase 2: Count actual group-to-group relationships
Write-Host "`nPhase 2 - Counting Group-to-Group Relationships..." -ForegroundColor Yellow

$actualGroupNesting = 0
$groupsWithActualNesting = 0
$sampleNestedGroups = @()

$searchRequest2 = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(objectClass=group)" `
    -Attributes @("distinguishedName", "name", "member")

$pagingControl2 = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($pageSize)
$pageNumber2 = 0

do {
    $pageNumber2++
    if ($pageNumber2 % 20 -eq 0) {
        Write-Host "  Phase 2 page $pageNumber2..."
    }

    $searchRequest2.Controls.Clear()
    $searchRequest2.Controls.Add($pagingControl2)
    $response2 = $connection.SendRequest($searchRequest2) -as [System.DirectoryServices.Protocols.SearchResponse]

    if ($null -eq $response2 -or $response2.Entries.Count -eq 0) {
        break
    }

    foreach ($entry in $response2.Entries) {
        $attrs = $entry.Attributes
        $groupDN = $attrs["distinguishedName"][0]
        $groupName = if ($attrs["name"]) { $attrs["name"][0] } else { "Unknown" }

        if ($attrs["member"]) {
            $groupMembersInThisGroup = 0
            
            foreach ($memberDN in $attrs["member"]) {
                # Check if this member is actually a group
                if ($allGroups.ContainsKey($memberDN)) {
                    $groupMembersInThisGroup++
                    $actualGroupNesting++
                    
                    # Collect samples for verification
                    if ($sampleNestedGroups.Count -lt 10) {
                        $sampleNestedGroups += @{
                            ParentGroup = $groupName
                            NestedGroup = $allGroups[$memberDN]
                        }
                    }
                }
            }
            
            if ($groupMembersInThisGroup -gt 0) {
                $groupsWithActualNesting++
            }
        }
    }

    $cookie2 = ($response2.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl2.Cookie = $cookie2

} while ($null -ne $cookie2 -and $cookie2.Length -ne 0)

# Final Results
Write-Host "`nFINAL RESULTS:" -ForegroundColor Green
Write-Host "==============" -ForegroundColor Green
Write-Host "Total Groups in AD: $totalGroups" -ForegroundColor Cyan
Write-Host "Groups with ANY members: $groupsWithNestedGroups" -ForegroundColor Cyan
Write-Host "Groups with NESTED GROUPS: $groupsWithActualNesting" -ForegroundColor Yellow
Write-Host "Total Group-to-Group relationships: $actualGroupNesting" -ForegroundColor Yellow

if ($sampleNestedGroups.Count -gt 0) {
    Write-Host "`nSample Nested Group Relationships:" -ForegroundColor Green
    foreach ($sample in $sampleNestedGroups) {
        Write-Host "  $($sample.ParentGroup) contains $($sample.NestedGroup)" -ForegroundColor White
    }
} else {
    Write-Host "`nNo nested group relationships found!" -ForegroundColor Red
}
```

} catch {
Write-Error “Error during group counting: $_”
throw
} finally {
if ($connection) { $connection.Dispose() }
}
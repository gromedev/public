#Requires -Version 7.0
<#
.SYNOPSIS
Use EXACT same logic as debug script that worked, just count more
#>

# Import existing modules

Import-Module (Join-Path $PSScriptRoot “....\Modules\AD.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “....\Modules\Common.Functions.psm1”) -Force

# Get configuration

$config = Get-Config -ConfigPath (Join-Path $PSScriptRoot “....\Modules\giam-config.json”) -Force

Write-Host “EXACT DEBUG LOGIC: Using proven approach” -ForegroundColor Cyan
Write-Host “=======================================” -ForegroundColor Cyan

$allGroups = @{}
$totalNestedRelationships = 0
$groupsWithNestedGroups = 0
$sampleRelationships = @()

try {
$connection = New-LDAPConnection -Config $config.ActiveDirectory

```
Write-Host "Step 1: Collecting ALL groups (same as debug script)..." -ForegroundColor Yellow

# EXACT same collection logic as debug script
$searchRequest = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(objectClass=group)" `
    -Attributes @("distinguishedName", "name")

$pagingControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($config.ActiveDirectory.PageSize)
$pageNumber = 0

do {
    $pageNumber++
    if ($pageNumber % 50 -eq 0) {
        $currentMemory = (Get-Process -Id $pid).WorkingSet64 / 1GB
        Write-Host "  Page $pageNumber... Groups: $($allGroups.Count), Memory: $([Math]::Round($currentMemory,1))GB"
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
        
        $allGroups[$groupDN] = $groupName  # EXACT same as debug script
    }

    $cookie = ($response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl.Cookie = $cookie

} while ($null -ne $cookie -and $cookie.Length -ne 0)

Write-Host "Step 2: Analyzing groups with members (same as debug script)..." -ForegroundColor Yellow
Write-Host "Total groups collected: $($allGroups.Count)" -ForegroundColor Cyan

# EXACT same analysis logic as debug script
$searchRequest2 = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(&(objectClass=group)(member=*))" `
    -Attributes @("distinguishedName", "name", "member")

$pagingControl2 = New-Object System.DirectoryServices.Protocols.PageResultRequestControl(100)
$pageNumber2 = 0
$groupsProcessed = 0

do {
    $pageNumber2++
    if ($pageNumber2 % 50 -eq 0) {
        Write-Host "  Analysis page $pageNumber2... Found $totalNestedRelationships relationships"
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
        
        $groupsProcessed++
        $nestedGroupsInThisGroup = 0

        if ($attrs["member"]) {
            foreach ($memberDN in $attrs["member"]) {
                # EXACT same check as debug script
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
        }

        if ($nestedGroupsInThisGroup -gt 0) {
            $groupsWithNestedGroups++
        }

        # Progress every 500 groups
        if ($groupsProcessed % 500 -eq 0) {
            Write-Host "    Processed $groupsProcessed groups..."
        }
    }

    $cookie2 = ($response2.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl2.Cookie = $cookie2

} while ($null -ne $cookie2 -and $cookie2.Length -ne 0)

# Results
Write-Host "`nFINAL RESULTS:" -ForegroundColor Green
Write-Host "==============" -ForegroundColor Green
Write-Host "Groups in lookup table: $($allGroups.Count)" -ForegroundColor Cyan
Write-Host "Groups with members processed: $groupsProcessed" -ForegroundColor Cyan
Write-Host "Groups with nested groups: $groupsWithNestedGroups" -ForegroundColor Yellow
Write-Host "Total nested relationships: $totalNestedRelationships" -ForegroundColor Yellow

if ($sampleRelationships.Count -gt 0) {
    Write-Host "`nFirst 10 relationships found:" -ForegroundColor Green
    foreach ($rel in $sampleRelationships[0..9]) {
        Write-Host "  '$($rel.ParentGroup)' → '$($rel.NestedGroup)'" -ForegroundColor White
    }
} else {
    Write-Host "`n❌ STILL ZERO - Something else is wrong!" -ForegroundColor Red
    Write-Host "Debug script found 9 relationships in 10 groups" -ForegroundColor Yellow
    Write-Host "This should find thousands in $groupsProcessed groups" -ForegroundColor Yellow
}
```

} catch {
Write-Error “Error: $_”
throw
} finally {
if ($connection) { $connection.Dispose() }
}
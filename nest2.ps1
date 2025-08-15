#Requires -Version 7.0
<#
.SYNOPSIS
Do EXACTLY what debug script did - same order, same timing
#>

# Import existing modules

Import-Module (Join-Path $PSScriptRoot “....\Modules\AD.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “....\Modules\Common.Functions.psm1”) -Force

# Get configuration

$config = Get-Config -ConfigPath (Join-Path $PSScriptRoot “....\Modules\giam-config.json”) -Force

Write-Host “EXACT DEBUG ORDER: Replicating debug script exactly” -ForegroundColor Cyan
Write-Host “==================================================” -ForegroundColor Cyan

$allGroups = @{}
$sampleGroupsWithMembers = @()

try {
$connection = New-LDAPConnection -Config $config.ActiveDirectory

```
Write-Host "Step 1: Collecting samples (EXACTLY like debug script)..." -ForegroundColor Yellow

# EXACT same first query as debug script
$searchRequest = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(&(objectClass=group)(member=*))" `
    -Attributes @("distinguishedName", "name", "member")

$pageSize = 100  # Same as debug script
$pagingControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($pageSize)

$searchRequest.Controls.Add($pagingControl)
$response = $connection.SendRequest($searchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

# Collect ALL groups from first page, not just 50 samples
Write-Host "Processing first page with $($response.Entries.Count) groups..."

foreach ($entry in $response.Entries) {
    $attrs = $entry.Attributes
    $groupDN = $attrs["distinguishedName"][0]
    $groupName = if ($attrs["name"]) { $attrs["name"][0] } else { "Unknown" }
    
    if ($attrs["member"]) {
        $memberCount = $attrs["member"].Count
        $allMembers = @()
        
        # Store ALL members, not just first 3
        foreach ($memberDN in $attrs["member"]) {
            $allMembers += $memberDN
        }
        
        $sampleGroupsWithMembers += @{
            GroupName = $groupName
            GroupDN = $groupDN
            MemberCount = $memberCount
            AllMembers = $allMembers
        }
    }
}

Write-Host "Step 2: Building full group lookup (EXACTLY like debug script)..." -ForegroundColor Yellow

# EXACT same second query as debug script
$searchRequest2 = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(objectClass=group)" `
    -Attributes @("distinguishedName", "name")

$pagingControl2 = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($config.ActiveDirectory.PageSize)
$pageNumber = 0

do {
    $pageNumber++
    if ($pageNumber % 50 -eq 0) {
        Write-Host "  Building lookup page $pageNumber... (total so far: $($allGroups.Count))"
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
        
        $allGroups[$groupDN] = $groupName  # EXACT same as debug script
    }

    $cookie2 = ($response2.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl2.Cookie = $cookie2

} while ($null -ne $cookie2 -and $cookie2.Length -ne 0)

Write-Host "Step 3: Analyzing samples (EXACTLY like debug script)..." -ForegroundColor Yellow
Write-Host "Total groups in lookup: $($allGroups.Count)" -ForegroundColor Cyan
Write-Host "Sample groups to analyze: $($sampleGroupsWithMembers.Count)" -ForegroundColor Cyan

$totalNestedRelationships = 0
$groupsWithNesting = 0

# EXACT same analysis as debug script
foreach ($sample in $sampleGroupsWithMembers) {
    $nestedGroupsInThisGroup = 0
    
    foreach ($memberDN in $sample.AllMembers) {
        # EXACT same check as debug script
        if ($allGroups.ContainsKey($memberDN)) {
            $nestedGroupName = $allGroups[$memberDN]
            $nestedGroupsInThisGroup++
            $totalNestedRelationships++
            
            Write-Host "  ✓ FOUND: '$($sample.GroupName)' → '$nestedGroupName'" -ForegroundColor Green
        }
    }
    
    if ($nestedGroupsInThisGroup -gt 0) {
        $groupsWithNesting++
    }
}

Write-Host "`nRESULTS FROM FIRST PAGE ONLY:" -ForegroundColor Yellow
Write-Host "Groups analyzed: $($sampleGroupsWithMembers.Count)" -ForegroundColor Cyan
Write-Host "Groups with nesting: $groupsWithNesting" -ForegroundColor Yellow
Write-Host "Total relationships: $totalNestedRelationships" -ForegroundColor Yellow

if ($totalNestedRelationships -gt 0) {
    Write-Host "`n✓ SUCCESS: Found relationships using exact debug logic!" -ForegroundColor Green
    Write-Host "The issue is with processing ALL pages, not the core logic" -ForegroundColor Yellow
} else {
    Write-Host "`n❌ FAILED: Even exact debug replication finds nothing!" -ForegroundColor Red
    Write-Host "Something fundamental is different between runs" -ForegroundColor Yellow
}
```

} catch {
Write-Error “Error: $_”
throw
} finally {
if ($connection) { $connection.Dispose() }
}
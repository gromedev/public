#Requires -Version 7.0
<#
.SYNOPSIS
Debug - Why nested group detection is failing
#>

# Import existing modules

Import-Module (Join-Path $PSScriptRoot “....\Modules\AD.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “....\Modules\Common.Functions.psm1”) -Force

# Get configuration

$config = Get-Config -ConfigPath (Join-Path $PSScriptRoot “....\Modules\giam-config.json”) -Force

Write-Host “DEBUG: Investigating Nested Group Detection” -ForegroundColor Cyan
Write-Host “===========================================” -ForegroundColor Cyan

$allGroups = @{}
$sampleGroupsWithMembers = @()

try {
# Create LDAP connection
$connection = New-LDAPConnection -Config $config.ActiveDirectory

```
Write-Host "Step 1: Collecting first 50 groups with members for analysis..." -ForegroundColor Yellow

# Search for groups with members
$searchRequest = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(&(objectClass=group)(member=*))" `
    -Attributes @("distinguishedName", "name", "member")

$pageSize = 100
$pagingControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($pageSize)

$searchRequest.Controls.Add($pagingControl)
$response = $connection.SendRequest($searchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

$samplesCollected = 0
foreach ($entry in $response.Entries) {
    if ($samplesCollected -ge 50) { break }
    
    $attrs = $entry.Attributes
    $groupDN = $attrs["distinguishedName"][0]
    $groupName = if ($attrs["name"]) { $attrs["name"][0] } else { "Unknown" }
    
    if ($attrs["member"]) {
        $memberCount = $attrs["member"].Count
        $firstFewMembers = @()
        
        # Get first 3 members for analysis
        for ($i = 0; $i -lt [Math]::Min(3, $memberCount); $i++) {
            $firstFewMembers += $attrs["member"][$i]
        }
        
        $sampleGroupsWithMembers += @{
            GroupName = $groupName
            GroupDN = $groupDN
            MemberCount = $memberCount
            SampleMembers = $firstFewMembers
        }
        $samplesCollected++
    }
}

Write-Host "Step 2: Collecting ALL group DNs for comparison..." -ForegroundColor Yellow

# Now collect ALL groups to build our lookup
$searchRequest2 = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(objectClass=group)" `
    -Attributes @("distinguishedName", "name")

$pagingControl2 = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($config.ActiveDirectory.PageSize)
$pageNumber = 0

do {
    $pageNumber++
    if ($pageNumber % 50 -eq 0) {
        Write-Host "  Collecting groups page $pageNumber... (total so far: $($allGroups.Count))"
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
        
        $allGroups[$groupDN] = $groupName
    }

    $cookie2 = ($response2.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl2.Cookie = $cookie2

} while ($null -ne $cookie2 -and $cookie2.Length -ne 0)

Write-Host "Step 3: Analyzing sample groups for nested group patterns..." -ForegroundColor Yellow
Write-Host "Total groups collected: $($allGroups.Count)" -ForegroundColor Cyan
Write-Host "Sample groups with members: $($sampleGroupsWithMembers.Count)" -ForegroundColor Cyan

$groupMembersFound = 0
$userMembersFound = 0
$computerMembersFound = 0
$unknownMembersFound = 0

foreach ($sample in $sampleGroupsWithMembers[0..9]) {  # First 10 samples
    Write-Host "`n--- Group: $($sample.GroupName) (Members: $($sample.MemberCount)) ---" -ForegroundColor Green
    
    foreach ($memberDN in $sample.SampleMembers) {
        Write-Host "  Member DN: $memberDN" -ForegroundColor Gray
        
        # Check what type of object this is
        if ($allGroups.ContainsKey($memberDN)) {
            Write-Host "    ✓ IS A GROUP: $($allGroups[$memberDN])" -ForegroundColor Green
            $groupMembersFound++
        } elseif ($memberDN -match "CN=.*,CN=Users,") {
            Write-Host "    - Is a user (in Users container)" -ForegroundColor Yellow
            $userMembersFound++
        } elseif ($memberDN -match "CN=.*,CN=Computers,") {
            Write-Host "    - Is a computer (in Computers container)" -ForegroundColor Yellow  
            $computerMembersFound++
        } elseif ($memberDN -match "CN=.*,OU=.*") {
            Write-Host "    - Is in an OU (likely user/computer)" -ForegroundColor Yellow
            $userMembersFound++
        } else {
            Write-Host "    ? Unknown object type" -ForegroundColor Red
            $unknownMembersFound++
        }
    }
}

Write-Host "`nMEMBER TYPE ANALYSIS:" -ForegroundColor Yellow
Write-Host "Group members found: $groupMembersFound" -ForegroundColor Green
Write-Host "User members found: $userMembersFound" -ForegroundColor Cyan
Write-Host "Computer members found: $computerMembersFound" -ForegroundColor Cyan
Write-Host "Unknown members found: $unknownMembersFound" -ForegroundColor Red

# If we found some group members, show the exact matching logic
if ($groupMembersFound -gt 0) {
    Write-Host "`n✓ NESTED GROUPS DETECTED! The logic should work." -ForegroundColor Green
    Write-Host "The issue might be in the counting logic of the main script." -ForegroundColor Yellow
} else {
    Write-Host "`n✗ NO NESTED GROUPS FOUND IN SAMPLES" -ForegroundColor Red
    Write-Host "This suggests either:" -ForegroundColor Yellow
    Write-Host "1. Your AD doesn't use nested groups" -ForegroundColor White
    Write-Host "2. Groups are in different OUs/containers than expected" -ForegroundColor White
    Write-Host "3. Our DN matching logic needs adjustment" -ForegroundColor White
}
```

} catch {
Write-Error “Error during nested group debugging: $_”
throw
} finally {
if ($connection) { $connection.Dispose() }
}
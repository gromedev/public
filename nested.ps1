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
        
        # Store all members first, we'll filter later
        $allMembers = @()
        if ($attrs["member"]) {
            foreach ($memberDN in $attrs["member"]) {
                $allMembers += $memberDN
            }
        }
        $groupMembers[$groupDN] = $allMembers
    }
    
    $cookie = ($response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl.Cookie = $cookie
    
} while ($null -ne $cookie -and $cookie.Length -ne 0)

Write-Host "Found $($allGroups.Count) groups"

# Now filter members to only include actual groups
Write-Host "Filtering group members..."
$filteredGroupMembers = @{}
$totalGroupMemberships = 0

foreach ($groupDN in $groupMembers.Keys) {
    $nestedGroups = @()
    foreach ($memberDN in $groupMembers[$groupDN]) {
        # Only include if the member is actually a group we found
        if ($allGroups.ContainsKey($memberDN)) {
            $nestedGroups += $memberDN
            $totalGroupMemberships++
        }
    }
    $filteredGroupMembers[$groupDN] = $nestedGroups
}

Write-Host "Found $totalGroupMemberships total group-in-group memberships"

# Build nested structure
Write-Host "Building nested structure..."

function Get-NestedGroups {
    param($GroupDN)
    
    $nestedGroups = @()
    foreach ($memberDN in $filteredGroupMembers[$GroupDN]) {
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
foreach ($groupDN in $filteredGroupMembers.Keys) {
    foreach ($memberDN in $filteredGroupMembers[$groupDN]) {
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

# Debug output
if ($rootGroups.Count -eq 0) {
    Write-Warning "No root groups with nested groups found!"
    
    # Show some stats for debugging
    $groupsWithMembers = 0
    foreach ($groupDN in $filteredGroupMembers.Keys) {
        if ($filteredGroupMembers[$groupDN].Count -gt 0) {
            $groupsWithMembers++
            if ($groupsWithMembers -le 5) {
                Write-Host "Group with nested groups: $($allGroups[$groupDN]) has $($filteredGroupMembers[$groupDN].Count) nested groups"
            }
        }
    }
    Write-Host "Total groups with nested groups: $groupsWithMembers"
    
    # Create simple list instead
    $allGroupsList = @()
    foreach ($groupDN in $allGroups.Keys) {
        if ($filteredGroupMembers[$groupDN].Count -gt 0) {
            $memberNames = @()
            foreach ($memberDN in $filteredGroupMembers[$groupDN]) {
                if ($allGroups.ContainsKey($memberDN)) {
                    $memberNames += $allGroups[$memberDN]
                }
            }
            if ($memberNames.Count -gt 0) {
                $allGroupsList += @{
                    Name = $allGroups[$groupDN]
                    NestedGroupNames = $memberNames
                }
            }
        }
    }
    $rootGroups = $allGroupsList
    Write-Host "Created flat list with $($rootGroups.Count) groups"
}

# Output to JSON
$outputPath = "C:\temp\nested.json"

# Ensure temp directory exists and is writable
try {
    if (-not (Test-Path "C:\temp")) {
        Write-Host "Creating C:\temp directory..."
        New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null
    }
    
    # Test write access
    $testFile = "C:\temp\test_write.tmp"
    "test" | Set-Content -Path $testFile -ErrorAction Stop
    Remove-Item $testFile -ErrorAction SilentlyContinue
    Write-Host "C:\temp is writable"
    
} catch {
    Write-Warning "Cannot write to C:\temp: $_"
    $outputPath = ".\nested.json"
    Write-Host "Using current directory instead: $outputPath"
}

try {
    Write-Host "Converting to JSON..."
    
    # If still no groups, create empty structure
    if ($rootGroups.Count -eq 0) {
        $rootGroups = @()
        Write-Host "Creating empty JSON structure"
    }
    
    $jsonContent = $rootGroups | ConvertTo-Json -Depth 20
    
    Write-Host "Writing to file..."
    $jsonContent | Set-Content -Path $outputPath -Encoding UTF8
    
    # Verify file was created
    if (Test-Path $outputPath) {
        $fileSize = (Get-Item $outputPath).Length
        Write-Host "Nested groups exported to: $outputPath" -ForegroundColor Green
        Write-Host "File size: $fileSize bytes" -ForegroundColor Green
        Write-Host "Groups in output: $($rootGroups.Count)" -ForegroundColor Green
    } else {
        Write-Error "File was not created!"
    }
    
} catch {
    Write-Error "Failed to create JSON: $_"
    
    # Try simple export
    Write-Host "Attempting simple text export..."
    $textPath = "C:\temp\nested.txt"
    $rootGroups | Out-String | Set-Content -Path $textPath
    Write-Host "Text export created: $textPath"
}

} catch {
Write-Error “Error collecting nested groups: $_”
throw
} finally {
if ($connection) { $connection.Dispose() }
[System.GC]::Collect()
}
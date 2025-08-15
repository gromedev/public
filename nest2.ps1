#Requires -Version 7.0
<#
.SYNOPSIS
WORKING script with recursive unlimited depth (up to 50 levels) - HashSet + Connection Refresh optimizations
#>

# Import existing modules

Import-Module (Join-Path $PSScriptRoot “….\Modules\AD.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “….\Modules\Common.Functions.psm1”) -Force

# Get configuration

$config = Get-Config -ConfigPath (Join-Path $PSScriptRoot “….\Modules\giam-config.json”) -Force

Write-Host “UNLIMITED DEPTH RECURSIVE: Up to 50 levels deep” -ForegroundColor Cyan
Write-Host “===============================================” -ForegroundColor Cyan

$processedGroups = 0
$script:totalRelationships = 0
$script:maxDepthFound = 0

# Setup JSON output file - EXACT SAME

$outputPath = “C:\temp\nested.json”
if (-not (Test-Path “C:\temp”)) {
New-Item -ItemType Directory -Path “C:\temp” -Force | Out-Null
}

# Connection refresh function to prevent LDAP connection degradation

function Refresh-LDAPConnection {
if ($script:connection) { $script:connection.Dispose() }
$script:connection = New-LDAPConnection -Config $config.ActiveDirectory
Write-Host “  → Refreshed LDAP connection” -ForegroundColor Yellow
}

# Recursive function using HashSet instead of hashtable

function Get-NestedGroupsRecursive {
param(
[string]$ParentGroupDN,
[string]$ParentGroupName,
[int]$CurrentDepth,
[int]$MaxDepth = 50,
[System.Collections.Generic.HashSet[string]]$VisitedGroups = [System.Collections.Generic.HashSet[string]]::new()
)

```
# Prevent infinite loops and excessive depth
if ($CurrentDepth -gt $MaxDepth -or $VisitedGroups.Contains($ParentGroupDN)) {
    return @()
}

# Track visited groups for this path
$VisitedGroups.Add($ParentGroupDN) | Out-Null

# Update max depth found
if ($CurrentDepth -gt $script:maxDepthFound) {
    $script:maxDepthFound = $CurrentDepth
}

$nestedGroups = @()

try {
    # EXACT same LDAP query that works
    $nestedSearchRequest = New-LDAPSearchRequest `
        -SearchBase $config.ActiveDirectory.OrganizationalUnit `
        -Filter "(&(objectCategory=group)(memberof=$ParentGroupDN))" `
        -Attributes @("distinguishedName", "name")

    $nestedResponse = $script:connection.SendRequest($nestedSearchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

    foreach ($nestedEntry in $nestedResponse.Entries) {
        $nestedAttrs = $nestedEntry.Attributes
        $nestedGroupDN = $nestedAttrs["distinguishedName"][0]
        $nestedGroupName = if ($nestedAttrs["name"]) { $nestedAttrs["name"][0] } else { "Unknown" }
        
        $script:totalRelationships++
        
        # Show progress for first few and deep nesting
        if ($script:totalRelationships -le 25 -or $CurrentDepth -ge 5) {
            $indent = "  " * ($CurrentDepth + 1)
            Write-Host "$indent✓ Depth $CurrentDepth`: '$ParentGroupName' → '$nestedGroupName'" -ForegroundColor Green
        }
        
        # Recursively get deeper levels (with HashSet copy instead of hashtable clone)
        $deeperNestedGroups = Get-NestedGroupsRecursive -ParentGroupDN $nestedGroupDN -ParentGroupName $nestedGroupName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -VisitedGroups ([System.Collections.Generic.HashSet[string]]::new($VisitedGroups))
        
        # Build this nested group entry
        $nestedGroupEntry = @{
            Name = $nestedGroupName
            Depth = $CurrentDepth
            NestedGroups = $deeperNestedGroups
        }
        
        $nestedGroups += $nestedGroupEntry
    }
}
catch {
    # Skip errors at this depth level
}

return $nestedGroups
```

}

# Start JSON array - EXACT SAME

Set-Content -Path $outputPath -Value “[” -Encoding UTF8

try {
$script:connection = New-LDAPConnection -Config $config.ActiveDirectory

```
Write-Host "Starting unlimited depth collection (up to 50 levels)..." -ForegroundColor Yellow
Write-Host "Writing directly to: $outputPath" -ForegroundColor Cyan

# EXACT SAME search setup
$searchRequest = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(objectClass=group)" `
    -Attributes @("distinguishedName", "name")

$pageSize = $config.ActiveDirectory.PageSize
$pagingControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($pageSize)
$pageNumber = 0
$firstGroup = $true

do {
    $pageNumber++
    
    # Refresh LDAP connection every 20 pages to prevent degradation
    if ($pageNumber % 20 -eq 0) {
        Refresh-LDAPConnection
    }
    
    # EXACT SAME memory reporting
    if ($pageNumber % 10 -eq 0) {
        $currentMemory = (Get-Process -Id $pid).WorkingSet64 / 1GB
        Write-Host "Page $pageNumber... Memory: $([Math]::Round($currentMemory,1))GB, Total: $script:totalRelationships relationships, Max Depth: $script:maxDepthFound"
    }

    $searchRequest.Controls.Clear()
    $searchRequest.Controls.Add($pagingControl)
    $response = $script:connection.SendRequest($searchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

    if ($null -eq $response -or $response.Entries.Count -eq 0) {
        break
    }

    foreach ($entry in $response.Entries) {
        $attrs = $entry.Attributes
        $parentGroupDN = $attrs["distinguishedName"][0]
        $parentGroupName = if ($attrs["name"]) { $attrs["name"][0] } else { "Unknown" }
        
        $processedGroups++

        # Use recursive function starting at depth 1
        try {
            $allNestedGroups = Get-NestedGroupsRecursive -ParentGroupDN $parentGroupDN -ParentGroupName $parentGroupName -CurrentDepth 1 -MaxDepth 50
            
            # Write parent group with ALL its nested levels
            if ($allNestedGroups.Count -gt 0) {
                $parentGroupEntry = @{
                    Name = $parentGroupName
                    Depth = 0
                    NestedGroups = $allNestedGroups
                }
                
                # Write immediately - PRETTY PRINTED for readability
                $comma = if ($firstGroup) { "" } else { "," }
                $jsonEntry = $comma + ($parentGroupEntry | ConvertTo-Json -Depth 60)  # Increased depth for JSON
                Add-Content -Path $outputPath -Value $jsonEntry -Encoding UTF8
                $firstGroup = $false
            }
        }
        catch {
            # Skip errors
        }

        # EXACT SAME progress reporting
        if ($processedGroups % 5000 -eq 0) {
            Write-Host "  Processed $processedGroups groups, wrote $script:totalRelationships relationships to file, Max Depth Found: $script:maxDepthFound"
        }

        # EXACT SAME memory cleanup
        if ($processedGroups % 1000 -eq 0) {
            [System.GC]::Collect()
        }
    }

    $cookie = ($response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl.Cookie = $cookie

} while ($null -ne $cookie -and $cookie.Length -ne 0)

# EXACT SAME closing
Add-Content -Path $outputPath -Value "]" -Encoding UTF8

# Enhanced final results
Write-Host "`nCOMPLETED!" -ForegroundColor Green
Write-Host "==========" -ForegroundColor Green
Write-Host "Total groups processed: $processedGroups" -ForegroundColor Cyan
Write-Host "Total relationships written: $script:totalRelationships" -ForegroundColor Yellow
Write-Host "Maximum depth found: $script:maxDepthFound levels" -ForegroundColor Magenta

if (Test-Path $outputPath) {
    $fileSize = (Get-Item $outputPath).Length
    Write-Host "JSON file: $outputPath" -ForegroundColor Green
    Write-Host "File size: $([Math]::Round($fileSize/1MB,1)) MB" -ForegroundColor Cyan
    Write-Host "✓ SUCCESS: Unlimited depth nested groups JSON created!" -ForegroundColor Green
    Write-Host "  Captures up to 50 levels of nesting depth" -ForegroundColor Cyan
    Write-Host "  Deepest nesting found: $script:maxDepthFound levels" -ForegroundColor Cyan
}
```

} catch {
Write-Error “Error in unlimited depth script: $_”

```
# EXACT SAME error handling
try {
    Add-Content -Path $outputPath -Value "]" -Encoding UTF8
} catch {}

throw
```

} finally {
if ($script:connection) { $script:connection.Dispose() }

```
# EXACT SAME cleanup
[System.GC]::Collect()

$finalMemory = (Get-Process -Id $pid).WorkingSet64 / 1GB
Write-Host "Final memory: $([Math]::Round($finalMemory,1))GB" -ForegroundColor Gray
```

}
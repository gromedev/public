#Requires -Version 7.0
<#
.SYNOPSIS
Use the memberOf approach from GitHub script with our LDAP connection
#>

# Import existing modules

Import-Module (Join-Path $PSScriptRoot “....\Modules\AD.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “....\Modules\Common.Functions.psm1”) -Force

# Get configuration

$config = Get-Config -ConfigPath (Join-Path $PSScriptRoot “....\Modules\giam-config.json”) -Force

Write-Host “MEMBEROF APPROACH: Using reverse lookup method” -ForegroundColor Cyan
Write-Host “================================================” -ForegroundColor Cyan

$nestedRelationships = @()
$processedGroups = 0

try {
$connection = New-LDAPConnection -Config $config.ActiveDirectory

```
Write-Host "Step 1: Find all groups that are members of other groups..." -ForegroundColor Yellow

# Use the GitHub script's approach: find groups that have memberOf
$searchRequest = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(&(objectCategory=group)(memberOf=*))" `
    -Attributes @("distinguishedName", "name", "memberOf")

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
        $nestedGroupDN = $attrs["distinguishedName"][0]
        $nestedGroupName = if ($attrs["name"]) { $attrs["name"][0] } else { "Unknown" }
        
        $processedGroups++

        # This group is a member of other groups
        if ($attrs["memberOf"]) {
            foreach ($parentGroupDN in $attrs["memberOf"]) {
                # Get parent group name
                try {
                    $parentSearchRequest = New-LDAPSearchRequest `
                        -SearchBase $parentGroupDN `
                        -Filter "(objectClass=group)" `
                        -Attributes @("name")

                    $parentResponse = $connection.SendRequest($parentSearchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]
                    
                    if ($parentResponse.Entries.Count -gt 0) {
                        $parentAttrs = $parentResponse.Entries[0].Attributes
                        $parentGroupName = if ($parentAttrs["name"]) { $parentAttrs["name"][0] } else { "Unknown" }
                        
                        $nestedRelationships += @{
                            ParentGroup = $parentGroupName
                            ParentGroupDN = $parentGroupDN
                            NestedGroup = $nestedGroupName
                            NestedGroupDN = $nestedGroupDN
                        }
                    }
                }
                catch {
                    # Parent might not be a group, skip
                }
            }
        }

        if ($processedGroups % 100 -eq 0) {
            Write-Host "  Processed $processedGroups groups, found $($nestedRelationships.Count) relationships"
        }
    }

    $cookie = ($response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl.Cookie = $cookie

} while ($null -ne $cookie -and $cookie.Length -ne 0)

# Results
Write-Host "`nFINAL RESULTS:" -ForegroundColor Green
Write-Host "==============" -ForegroundColor Green
Write-Host "Groups processed: $processedGroups" -ForegroundColor Cyan
Write-Host "Nested relationships found: $($nestedRelationships.Count)" -ForegroundColor Yellow

if ($nestedRelationships.Count -gt 0) {
    Write-Host "`nFirst 10 relationships:" -ForegroundColor Green
    foreach ($rel in $nestedRelationships[0..9]) {
        Write-Host "  '$($rel.ParentGroup)' → '$($rel.NestedGroup)'" -ForegroundColor White
    }
    
    Write-Host "`n✓ SUCCESS: MemberOf approach works!" -ForegroundColor Green
    
    # Now create JSON output
    Write-Host "`nCreating JSON output..." -ForegroundColor Yellow
    
    # Group by parent
    $groupedByParent = @{}
    foreach ($rel in $nestedRelationships) {
        if (-not $groupedByParent.ContainsKey($rel.ParentGroup)) {
            $groupedByParent[$rel.ParentGroup] = @()
        }
        $groupedByParent[$rel.ParentGroup] += $rel.NestedGroup
    }
    
    # Create hierarchical structure
    $hierarchical = @()
    foreach ($parentGroup in $groupedByParent.Keys) {
        $hierarchical += @{
            Name = $parentGroup
            NestedGroups = $groupedByParent[$parentGroup] | ForEach-Object { 
                @{ Name = $_ }
            }
        }
    }
    
    # Export to JSON
    $outputPath = "C:\temp\nested.json"
    if (-not (Test-Path "C:\temp")) {
        New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null
    }
    
    $hierarchical | ConvertTo-Json -Depth 10 | Set-Content -Path $outputPath -Encoding UTF8
    
    Write-Host "✓ JSON exported to: $outputPath" -ForegroundColor Green
    Write-Host "File contains $($hierarchical.Count) parent groups" -ForegroundColor Cyan
    
} else {
    Write-Host "`n❌ Still no relationships found with memberOf approach" -ForegroundColor Red
}
```

} catch {
Write-Error “Error: $_”
throw
} finally {
if ($connection) { $connection.Dispose() }
}
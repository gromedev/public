#Requires -Version 7.0
<#
.SYNOPSIS
Apply GitHub script logic to ALL groups in AD
.DESCRIPTION
Takes the single-group logic from GitHub script and applies it to every group in the domain
#>

# Import existing modules

Import-Module (Join-Path $PSScriptRoot “....\Modules\AD.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “....\Modules\Common.Functions.psm1”) -Force

# Get configuration

$config = Get-Config -ConfigPath (Join-Path $PSScriptRoot “....\Modules\giam-config.json”) -Force

Write-Host “GITHUB LOGIC ADAPTED: Apply single-group logic to all groups” -ForegroundColor Cyan
Write-Host “=============================================================” -ForegroundColor Cyan

$allNestedRelationships = @()
$processedGroups = 0
$groupsWithNesting = 0

try {
$connection = New-LDAPConnection -Config $config.ActiveDirectory

```
Write-Host "Step 1: Get all groups to process..." -ForegroundColor Yellow

# Get all groups (same as GitHub script gets the input group)
$searchRequest = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(objectClass=group)" `
    -Attributes @("distinguishedName", "name")

$pageSize = $config.ActiveDirectory.PageSize
$pagingControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($pageSize)
$pageNumber = 0

Write-Host "Step 2: For each group, apply GitHub script logic..." -ForegroundColor Yellow

do {
    $pageNumber++
    Write-Host "Processing groups page $pageNumber..."

    $searchRequest.Controls.Clear()
    $searchRequest.Controls.Add($pagingControl)
    $response = $connection.SendRequest($searchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

    if ($null -eq $response -or $response.Entries.Count -eq 0) {
        break
    }

    foreach ($entry in $response.Entries) {
        $attrs = $entry.Attributes
        $parentGroupDN = $attrs["distinguishedName"][0]
        $parentGroupName = if ($attrs["name"]) { $attrs["name"][0] } else { "Unknown" }
        
        $processedGroups++

        # GITHUB SCRIPT LOGIC: For this group, find groups that are members of it
        # Original: Get-ADGroup -LDAPFilter "(&(objectCategory=group)(memberof=$($ADGrp.DistinguishedName)))"
        # Adapted: Use our LDAP connection with same filter
        
        try {
            $nestedSearchRequest = New-LDAPSearchRequest `
                -SearchBase $config.ActiveDirectory.OrganizationalUnit `
                -Filter "(&(objectCategory=group)(memberof=$parentGroupDN))" `
                -Attributes @("distinguishedName", "name", "canonicalname")

            $nestedResponse = $connection.SendRequest($nestedSearchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

            # GITHUB SCRIPT LOGIC: Process each nested group found
            if ($nestedResponse.Entries.Count -gt 0) {
                $groupsWithNesting++
                
                foreach ($nestedEntry in $nestedResponse.Entries) {
                    $nestedAttrs = $nestedEntry.Attributes
                    $nestedGroupDN = $nestedAttrs["distinguishedName"][0]
                    $nestedGroupName = if ($nestedAttrs["name"]) { $nestedAttrs["name"][0] } else { "Unknown" }
                    $nestedCanonicalName = if ($nestedAttrs["canonicalname"]) { $nestedAttrs["canonicalname"][0] } else { "" }

                    # GITHUB SCRIPT LOGIC: Create the same output structure
                    $nestedGroupInfo = @{
                        ParentGroup = $parentGroupName
                        ParentGroupDN = $parentGroupDN
                        NestedGroup = $nestedGroupName
                        NestedGroupDN = $nestedGroupDN
                        ObjectPath = $nestedCanonicalName
                    }

                    $allNestedRelationships += $nestedGroupInfo

                    # Show first few to verify logic
                    if ($allNestedRelationships.Count -le 10) {
                        Write-Host "  ✓ FOUND: '$parentGroupName' contains '$nestedGroupName'" -ForegroundColor Green
                    }
                }

                # GITHUB SCRIPT LOGIC: Go one level deeper (2nd level nesting)
                foreach ($nestedEntry in $nestedResponse.Entries) {
                    $nestedAttrs = $nestedEntry.Attributes
                    $nestedGroupDN = $nestedAttrs["distinguishedName"][0]
                    $nestedGroupName = if ($nestedAttrs["name"]) { $nestedAttrs["name"][0] } else { "Unknown" }

                    # Look for groups nested inside this nested group
                    try {
                        $subNestedSearchRequest = New-LDAPSearchRequest `
                            -SearchBase $config.ActiveDirectory.OrganizationalUnit `
                            -Filter "(&(objectCategory=group)(memberof=$nestedGroupDN))" `
                            -Attributes @("distinguishedName", "name", "canonicalname")

                        $subNestedResponse = $connection.SendRequest($subNestedSearchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

                        if ($subNestedResponse.Entries.Count -gt 0) {
                            foreach ($subNestedEntry in $subNestedResponse.Entries) {
                                $subNestedAttrs = $subNestedEntry.Attributes
                                $subNestedGroupDN = $subNestedAttrs["distinguishedName"][0]
                                $subNestedGroupName = if ($subNestedAttrs["name"]) { $subNestedAttrs["name"][0] } else { "Unknown" }
                                $subNestedCanonicalName = if ($subNestedAttrs["canonicalname"]) { $subNestedAttrs["canonicalname"][0] } else { "" }

                                # GITHUB SCRIPT LOGIC: Create output for 2nd level nesting
                                $subNestedGroupInfo = @{
                                    ParentGroup = $nestedGroupName  # The nested group becomes the parent
                                    ParentGroupDN = $nestedGroupDN
                                    NestedGroup = $subNestedGroupName
                                    NestedGroupDN = $subNestedGroupDN
                                    ObjectPath = $subNestedCanonicalName
                                }

                                $allNestedRelationships += $subNestedGroupInfo

                                # Show first few 2nd level relationships
                                if ($allNestedRelationships.Count -le 15) {
                                    Write-Host "  ✓ 2ND LEVEL: '$nestedGroupName' contains '$subNestedGroupName'" -ForegroundColor Yellow
                                }
                            }
                        }
                    }
                    catch {
                        # Skip errors on 2nd level lookup
                    }
                }
            }
        }
        catch {
            # Skip errors looking up nested groups for this parent
        }

        # Progress reporting
        if ($processedGroups % 1000 -eq 0) {
            Write-Host "  Processed $processedGroups groups, found $($allNestedRelationships.Count) relationships in $groupsWithNesting groups"
        }
    }

    $cookie = ($response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl.Cookie = $cookie

} while ($null -ne $cookie -and $cookie.Length -ne 0)

# Final Results
Write-Host "`nFINAL RESULTS:" -ForegroundColor Green
Write-Host "==============" -ForegroundColor Green
Write-Host "Total groups processed: $processedGroups" -ForegroundColor Cyan
Write-Host "Groups with nesting: $groupsWithNesting" -ForegroundColor Yellow
Write-Host "Total nested relationships: $($allNestedRelationships.Count)" -ForegroundColor Yellow

if ($allNestedRelationships.Count -gt 0) {
    Write-Host "`n✓ SUCCESS: GitHub logic adaptation works!" -ForegroundColor Green
    
    # Create JSON output following GitHub script structure
    Write-Host "`nCreating JSON output..." -ForegroundColor Yellow
    
    # Group relationships by parent (following GitHub script output pattern)
    $groupedByParent = @{}
    foreach ($rel in $allNestedRelationships) {
        if (-not $groupedByParent.ContainsKey($rel.ParentGroup)) {
            $groupedByParent[$rel.ParentGroup] = @()
        }
        
        # Follow GitHub script structure
        $groupedByParent[$rel.ParentGroup] += @{
            Name = $rel.NestedGroup
            DistinguishedName = $rel.NestedGroupDN
            ObjectPath = $rel.ObjectPath
        }
    }
    
    # Create hierarchical output
    $hierarchicalOutput = @()
    foreach ($parentGroup in $groupedByParent.Keys) {
        $hierarchicalOutput += @{
            Name = $parentGroup
            NestedGroups = $groupedByParent[$parentGroup]
        }
    }
    
    # Export to JSON
    $outputPath = "C:\temp\nested.json"
    if (-not (Test-Path "C:\temp")) {
        New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null
    }
    
    $hierarchicalOutput | ConvertTo-Json -Depth 10 | Set-Content -Path $outputPath -Encoding UTF8
    
    Write-Host "✓ JSON exported to: $outputPath" -ForegroundColor Green
    Write-Host "File contains $($hierarchicalOutput.Count) parent groups with nesting" -ForegroundColor Cyan
    
    # Show sample of what was found
    Write-Host "`nSample relationships found:" -ForegroundColor Green
    foreach ($rel in $allNestedRelationships[0..4]) {
        Write-Host "  '$($rel.ParentGroup)' → '$($rel.NestedGroup)'" -ForegroundColor White
    }
    
} else {
    Write-Host "`n❌ GitHub logic adaptation still found no relationships" -ForegroundColor Red
    Write-Host "This suggests your AD may not use nested groups" -ForegroundColor Yellow
}
```

} catch {
Write-Error “Error in GitHub logic adaptation: $_”
throw
} finally {
if ($connection) { $connection.Dispose() }
}
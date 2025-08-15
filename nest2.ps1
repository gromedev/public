#Requires -Version 7.0
<#
.SYNOPSIS
EXACT working script as base, just extend the depth and fix nesting structure
#>

# Import existing modules

Import-Module (Join-Path $PSScriptRoot “....\Modules\AD.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “....\Modules\Common.Functions.psm1”) -Force

# Get configuration

$config = Get-Config -ConfigPath (Join-Path $PSScriptRoot “....\Modules\giam-config.json”) -Force

Write-Host “EXACT WORKING BASE + EXTENDED DEPTH: Same logic, proper nesting” -ForegroundColor Cyan
Write-Host “=================================================================” -ForegroundColor Cyan

$processedGroups = 0
$totalRelationships = 0

# Setup JSON output file - EXACT SAME

$outputPath = “C:\temp\nested.json”
if (-not (Test-Path “C:\temp”)) {
New-Item -ItemType Directory -Path “C:\temp” -Force | Out-Null
}

# Start JSON array - EXACT SAME

Set-Content -Path $outputPath -Value “[” -Encoding UTF8

try {
$connection = New-LDAPConnection -Config $config.ActiveDirectory

```
Write-Host "Starting collection with extended depth..." -ForegroundColor Yellow
Write-Host "Writing directly to: $outputPath" -ForegroundColor Cyan

# EXACT SAME search setup
$searchRequest = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(objectClass=group)" `
    -Attributes @("distinguishedName", "name")

$pageSize = $config.ActiveDirectory.PageSize
$pagingControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($pageSize)
$pageNumber = 0
$firstGroup = $true  # FIXED: properly initialized

do {
    $pageNumber++
    
    # EXACT SAME memory reporting
    if ($pageNumber % 10 -eq 0) {
        $currentMemory = (Get-Process -Id $pid).WorkingSet64 / 1GB
        Write-Host "Page $pageNumber... Memory: $([Math]::Round($currentMemory,1))GB, Total: $totalRelationships relationships"
    }

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

        # EXACT SAME GitHub script logic
        try {
            $nestedSearchRequest = New-LDAPSearchRequest `
                -SearchBase $config.ActiveDirectory.OrganizationalUnit `
                -Filter "(&(objectCategory=group)(memberof=$parentGroupDN))" `
                -Attributes @("distinguishedName", "name")

            $nestedResponse = $connection.SendRequest($nestedSearchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

            if ($nestedResponse.Entries.Count -gt 0) {
                # Build nested groups array for this parent - EXACT SAME
                $nestedGroups = @()
                
                foreach ($nestedEntry in $nestedResponse.Entries) {
                    $nestedAttrs = $nestedEntry.Attributes
                    $nestedGroupName = if ($nestedAttrs["name"]) { $nestedAttrs["name"][0] } else { "Unknown" }
                    $nestedGroupDN = $nestedAttrs["distinguishedName"][0]

                    $totalRelationships++

                    # Show first few - EXACT SAME
                    if ($totalRelationships -le 10) {
                        Write-Host "  ✓ Level 1: '$parentGroupName' → '$nestedGroupName'" -ForegroundColor Green
                    }

                    # 2nd level nesting - SAME logic but FIXED structure
                    $level2Groups = @()
                    try {
                        $subNestedSearchRequest = New-LDAPSearchRequest `
                            -SearchBase $config.ActiveDirectory.OrganizationalUnit `
                            -Filter "(&(objectCategory=group)(memberof=$nestedGroupDN))" `
                            -Attributes @("distinguishedName", "name")

                        $subNestedResponse = $connection.SendRequest($subNestedSearchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

                        foreach ($subNestedEntry in $subNestedResponse.Entries) {
                            $subNestedAttrs = $subNestedEntry.Attributes
                            $subNestedGroupName = if ($subNestedAttrs["name"]) { $subNestedAttrs["name"][0] } else { "Unknown" }
                            $subNestedGroupDN = $subNestedAttrs["distinguishedName"][0]

                            $totalRelationships++

                            if ($totalRelationships -le 15) {
                                Write-Host "    ✓ Level 2: '$nestedGroupName' → '$subNestedGroupName'" -ForegroundColor Yellow
                            }

                            # 3rd level nesting - EXTEND the pattern
                            $level3Groups = @()
                            try {
                                $level3SearchRequest = New-LDAPSearchRequest `
                                    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
                                    -Filter "(&(objectCategory=group)(memberof=$subNestedGroupDN))" `
                                    -Attributes @("distinguishedName", "name")

                                $level3Response = $connection.SendRequest($level3SearchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

                                foreach ($level3Entry in $level3Response.Entries) {
                                    $level3Attrs = $level3Entry.Attributes
                                    $level3GroupName = if ($level3Attrs["name"]) { $level3Attrs["name"][0] } else { "Unknown" }
                                    $level3GroupDN = $level3Attrs["distinguishedName"][0]

                                    $totalRelationships++

                                    if ($totalRelationships -le 20) {
                                        Write-Host "      ✓ Level 3: '$subNestedGroupName' → '$level3GroupName'" -ForegroundColor Magenta
                                    }

                                    # 4th level nesting
                                    $level4Groups = @()
                                    try {
                                        $level4SearchRequest = New-LDAPSearchRequest `
                                            -SearchBase $config.ActiveDirectory.OrganizationalUnit `
                                            -Filter "(&(objectCategory=group)(memberof=$level3GroupDN))" `
                                            -Attributes @("name")

                                        $level4Response = $connection.SendRequest($level4SearchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

                                        foreach ($level4Entry in $level4Response.Entries) {
                                            $level4Attrs = $level4Entry.Attributes
                                            $level4GroupName = if ($level4Attrs["name"]) { $level4Attrs["name"][0] } else { "Unknown" }

                                            $level4Groups += @{ 
                                                Name = $level4GroupName
                                                Depth = 4
                                            }
                                            $totalRelationships++

                                            if ($totalRelationships -le 25) {
                                                Write-Host "        ✓ Level 4: '$level3GroupName' → '$level4GroupName'" -ForegroundColor Cyan
                                            }
                                        }
                                    }
                                    catch {
                                        # Skip 4th level errors
                                    }

                                    # Build level 3 entry with proper nesting
                                    $level3Groups += @{
                                        Name = $level3GroupName
                                        Depth = 3
                                        NestedGroups = $level4Groups
                                    }
                                }
                            }
                            catch {
                                # Skip 3rd level errors
                            }

                            # Build level 2 entry with proper nesting
                            $level2Groups += @{
                                Name = $subNestedGroupName
                                Depth = 2
                                NestedGroups = $level3Groups
                            }
                        }
                    }
                    catch {
                        # Skip 2nd level errors
                    }

                    # Build level 1 entry with proper nesting (FIXED from original)
                    $nestedGroups += @{
                        Name = $nestedGroupName
                        Depth = 1
                        NestedGroups = $level2Groups
                    }
                }

                # Write parent group - EXACT SAME as working script
                if ($nestedGroups.Count -gt 0) {
                    $parentGroupEntry = @{
                        Name = $parentGroupName
                        Depth = 0
                        NestedGroups = $nestedGroups
                    }
                    
                    # Write immediately - PRETTY PRINTED for readability
                    $comma = if ($firstGroup) { "" } else { "," }
                    $jsonEntry = $comma + ($parentGroupEntry | ConvertTo-Json -Depth 10)
                    Add-Content -Path $outputPath -Value $jsonEntry -Encoding UTF8
                    $firstGroup = $false
                }
            }
        }
        catch {
            # Skip errors - EXACT SAME
        }

        # EXACT SAME progress reporting
        if ($processedGroups % 5000 -eq 0) {
            Write-Host "  Processed $processedGroups groups, wrote $totalRelationships relationships to file"
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

# EXACT SAME final results
Write-Host "`nCOMPLETED!" -ForegroundColor Green
Write-Host "==========" -ForegroundColor Green
Write-Host "Total groups processed: $processedGroups" -ForegroundColor Cyan
Write-Host "Total relationships written: $totalRelationships" -ForegroundColor Yellow

if (Test-Path $outputPath) {
    $fileSize = (Get-Item $outputPath).Length
    Write-Host "JSON file: $outputPath" -ForegroundColor Green
    Write-Host "File size: $([Math]::Round($fileSize/1MB,1)) MB" -ForegroundColor Cyan
    Write-Host "✓ SUCCESS: Extended depth nested groups JSON created!" -ForegroundColor Green
    Write-Host "  Properly nested 4 levels deep" -ForegroundColor Cyan
}
```

} catch {
Write-Error “Error in extended script: $_”

```
# EXACT SAME error handling
try {
    Add-Content -Path $outputPath -Value "]" -Encoding UTF8
} catch {}

throw
```

} finally {
if ($connection) { $connection.Dispose() }

```
# EXACT SAME cleanup
[System.GC]::Collect()

$finalMemory = (Get-Process -Id $pid).WorkingSet64 / 1GB
Write-Host "Final memory: $([Math]::Round($finalMemory,1))GB" -ForegroundColor Gray
```

}
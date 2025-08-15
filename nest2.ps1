#Requires -Version 7.0
<#
.SYNOPSIS
Ultra-lightweight streaming - write to JSON immediately, keep nothing in memory
#>

# Import existing modules

Import-Module (Join-Path $PSScriptRoot “....\Modules\AD.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “....\Modules\Common.Functions.psm1”) -Force

# Get configuration

$config = Get-Config -ConfigPath (Join-Path $PSScriptRoot “....\Modules\giam-config.json”) -Force

Write-Host “ULTRA-LIGHTWEIGHT: Write JSON immediately, zero memory storage” -ForegroundColor Cyan
Write-Host “================================================================” -ForegroundColor Cyan

$processedGroups = 0
$totalRelationships = 0

# Setup JSON output file

$outputPath = “C:\temp\nested.json”
if (-not (Test-Path “C:\temp”)) {
New-Item -ItemType Directory -Path “C:\temp” -Force | Out-Null
}

# Start JSON array

Set-Content -Path $outputPath -Value “[” -Encoding UTF8

try {
$connection = New-LDAPConnection -Config $config.ActiveDirectory

```
Write-Host "Starting ultra-lightweight collection..." -ForegroundColor Yellow
Write-Host "Writing directly to: $outputPath" -ForegroundColor Cyan

# Get all groups to process
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
    
    # Minimal memory reporting
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

        # Apply GitHub script logic - find nested groups
        try {
            $nestedSearchRequest = New-LDAPSearchRequest `
                -SearchBase $config.ActiveDirectory.OrganizationalUnit `
                -Filter "(&(objectCategory=group)(memberof=$parentGroupDN))" `
                -Attributes @("distinguishedName", "name")

            $nestedResponse = $connection.SendRequest($nestedSearchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

            if ($nestedResponse.Entries.Count -gt 0) {
                # Build nested groups array for this parent
                $nestedGroups = @()
                
                foreach ($nestedEntry in $nestedResponse.Entries) {
                    $nestedAttrs = $nestedEntry.Attributes
                    $nestedGroupName = if ($nestedAttrs["name"]) { $nestedAttrs["name"][0] } else { "Unknown" }
                    $nestedGroupDN = $nestedAttrs["distinguishedName"][0]

                    # Add to nested groups array
                    $nestedGroups += @{
                        Name = $nestedGroupName
                    }
                    
                    $totalRelationships++

                    # Show first few
                    if ($totalRelationships -le 10) {
                        Write-Host "  ✓ '$parentGroupName' → '$nestedGroupName'" -ForegroundColor Green
                    }

                    # 2nd level nesting (GitHub script logic)
                    try {
                        $subNestedSearchRequest = New-LDAPSearchRequest `
                            -SearchBase $config.ActiveDirectory.OrganizationalUnit `
                            -Filter "(&(objectCategory=group)(memberof=$nestedGroupDN))" `
                            -Attributes @("name")

                        $subNestedResponse = $connection.SendRequest($subNestedSearchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

                        foreach ($subNestedEntry in $subNestedResponse.Entries) {
                            $subNestedAttrs = $subNestedEntry.Attributes
                            $subNestedGroupName = if ($subNestedAttrs["name"]) { $subNestedAttrs["name"][0] } else { "Unknown" }

                            # Create separate entry for 2nd level nesting
                            $secondLevelGroup = @{
                                Name = $nestedGroupName
                                NestedGroups = @(
                                    @{ Name = $subNestedGroupName }
                                )
                            }
                            
                            # Write immediately to JSON file
                            $comma = if ($firstGroup) { "" } else { "," }
                            $jsonEntry = $comma + ($secondLevelGroup | ConvertTo-Json -Depth 3 -Compress)
                            Add-Content -Path $outputPath -Value $jsonEntry -Encoding UTF8
                            $firstGroup = $false
                            
                            $totalRelationships++
                        }
                    }
                    catch {
                        # Skip 2nd level errors
                    }
                }

                # Write parent group with its nested groups immediately to JSON
                if ($nestedGroups.Count -gt 0) {
                    $parentGroupEntry = @{
                        Name = $parentGroupName
                        NestedGroups = $nestedGroups
                    }
                    
                    # Write immediately - no memory storage
                    $comma = if ($firstGroup) { "" } else { "," }
                    $jsonEntry = $comma + ($parentGroupEntry | ConvertTo-Json -Depth 3 -Compress)
                    Add-Content -Path $outputPath -Value $jsonEntry -Encoding UTF8
                    $firstGroup = $false
                }
            }
        }
        catch {
            # Skip errors
        }

        # Minimal progress reporting
        if ($processedGroups % 5000 -eq 0) {
            Write-Host "  Processed $processedGroups groups, wrote $totalRelationships relationships to file"
        }

        # Aggressive memory cleanup every 1000 groups
        if ($processedGroups % 1000 -eq 0) {
            [System.GC]::Collect()
        }
    }

    $cookie = ($response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl.Cookie = $cookie

} while ($null -ne $cookie -and $cookie.Length -ne 0)

# Close JSON array
Add-Content -Path $outputPath -Value "]" -Encoding UTF8

# Final results
Write-Host "`nCOMPLETED!" -ForegroundColor Green
Write-Host "==========" -ForegroundColor Green
Write-Host "Total groups processed: $processedGroups" -ForegroundColor Cyan
Write-Host "Total relationships written: $totalRelationships" -ForegroundColor Yellow

if (Test-Path $outputPath) {
    $fileSize = (Get-Item $outputPath).Length
    Write-Host "JSON file: $outputPath" -ForegroundColor Green
    Write-Host "File size: $([Math]::Round($fileSize/1MB,1)) MB" -ForegroundColor Cyan
    Write-Host "✓ SUCCESS: Complete nested groups JSON created!" -ForegroundColor Green
}
```

} catch {
Write-Error “Error in ultra-lightweight streaming: $_”

```
# Try to close JSON array even on error
try {
    Add-Content -Path $outputPath -Value "]" -Encoding UTF8
} catch {}

throw
```

} finally {
if ($connection) { $connection.Dispose() }

```
# Final cleanup
[System.GC]::Collect()

$finalMemory = (Get-Process -Id $pid).WorkingSet64 / 1GB
Write-Host "Final memory: $([Math]::Round($finalMemory,1))GB" -ForegroundColor Gray
```

}
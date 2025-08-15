#Requires -Version 7.0
<#
.SYNOPSIS
Visualizes AD group hierarchy from JSON output in tree format
.DESCRIPTION
Reads the JSON output from Collect-ADNestedGroups.ps1 and displays it as a readable tree structure
.EXAMPLE
.\Show-ADGroupHierarchy.ps1 -JsonPath “.\GIAM-ADNestedGroups_20241215_143022.json”
.\Show-ADGroupHierarchy.ps1 -JsonPath “.\GIAM-ADNestedGroups_20241215_143022.json” -GroupName “Domain Admins”
.\Show-ADGroupHierarchy.ps1 -JsonPath “.\GIAM-ADNestedGroups_20241215_143022.json” -MaxDisplayDepth 3
#>

[CmdletBinding()]
param(
[Parameter(Mandatory)]
[string]$JsonPath,                    # Path to the JSON file from Collect-ADNestedGroups.ps1

```
[string]$GroupName = $null,           # Optional: Show only specific group hierarchy
[int]$MaxDisplayDepth = 10,           # Maximum depth to display
[switch]$ShowStats,                   # Show detailed statistics
[switch]$ShowPaths,                   # Show full paths instead of tree structure
[switch]$OnlyGroupsWithNesting,       # Only show groups that contain other groups
[string]$OutputFile = $null           # Optional: Save output to file
```

)

function Show-GroupTree {
<#
.SYNOPSIS
Recursively displays group hierarchy in tree format
#>
param(
[object]$GroupData,
[string]$Prefix = “”,
[bool]$IsLast = $true,
[int]$CurrentDepth = 0,
[int]$MaxDepth = 10
)

```
if ($CurrentDepth -gt $MaxDepth) {
    return
}

# Skip groups without nesting if OnlyGroupsWithNesting is specified
if ($OnlyGroupsWithNesting -and $GroupData.NestedGroupCount -eq 0) {
    return
}

# Determine tree symbols
$currentSymbol = if ($IsLast) { "└── " } else { "├── " }
$nextPrefix = if ($IsLast) { "$Prefix    " } else { "$Prefix│   " }

# Format group information
$groupInfo = $GroupData.Name
if ($GroupData.NestedGroupCount -gt 0) {
    $groupInfo += " ($($GroupData.NestedGroupCount) nested)"
}
if ($GroupData.CircularReference) {
    $groupInfo += " [CIRCULAR]"
}

# Color coding based on depth and type
$color = switch ($CurrentDepth) {
    0 { "Cyan" }
    1 { "Yellow" }  
    2 { "Green" }
    3 { "Magenta" }
    default { "White" }
}

if ($GroupData.CircularReference) {
    $color = "Red"
}

# Output the current group
$output = "$Prefix$currentSymbol$groupInfo"
if ($OutputFile) {
    $output | Add-Content -Path $OutputFile
} else {
    Write-Host $output -ForegroundColor $color
}

# Process nested groups
if ($GroupData.NestedGroups -and $GroupData.NestedGroups.Count -gt 0) {
    for ($i = 0; $i -lt $GroupData.NestedGroups.Count; $i++) {
        $isLastNested = ($i -eq ($GroupData.NestedGroups.Count - 1))
        Show-GroupTree -GroupData $GroupData.NestedGroups[$i] -Prefix $nextPrefix -IsLast $isLastNested -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth
    }
}
```

}

function Show-GroupPaths {
<#
.SYNOPSIS
Shows group hierarchy as full paths
#>
param(
[object]$GroupData,
[string]$ParentPath = “”
)

```
$currentPath = if ($ParentPath) { "$ParentPath → $($GroupData.Name)" } else { $GroupData.Name }

# Skip groups without nesting if OnlyGroupsWithNesting is specified
if (-not $OnlyGroupsWithNesting -or $GroupData.NestedGroupCount -gt 0) {
    $pathInfo = "$currentPath"
    if ($GroupData.NestedGroupCount -gt 0) {
        $pathInfo += " [$($GroupData.NestedGroupCount) nested groups]"
    }
    if ($GroupData.CircularReference) {
        $pathInfo += " [CIRCULAR REFERENCE]"
    }
    
    if ($OutputFile) {
        $pathInfo | Add-Content -Path $OutputFile
    } else {
        $color = if ($GroupData.CircularReference) { "Red" } elseif ($GroupData.NestedGroupCount -gt 0) { "Green" } else { "White" }
        Write-Host $pathInfo -ForegroundColor $color
    }
}

# Process nested groups
if ($GroupData.NestedGroups -and $GroupData.NestedGroups.Count -gt 0) {
    foreach ($nestedGroup in $GroupData.NestedGroups) {
        Show-GroupPaths -GroupData $nestedGroup -ParentPath $currentPath
    }
}
```

}

function Show-Statistics {
<#
.SYNOPSIS
Displays detailed statistics about the group hierarchy
#>
param([object]$Data)

```
$stats = $Data.Statistics

Write-Host "`n" + "="*60 -ForegroundColor Yellow
Write-Host "AD GROUP HIERARCHY STATISTICS" -ForegroundColor Yellow
Write-Host "="*60 -ForegroundColor Yellow

Write-Host "Collection Information:" -ForegroundColor Cyan
Write-Host "  Generated At: $($Data.GeneratedAt)" -ForegroundColor White
Write-Host "  Root Group Filter: $(if ($Data.RootGroup) { $Data.RootGroup } else { 'All Groups' })" -ForegroundColor White
Write-Host "  Max Depth Limit: $($Data.MaxDepth)" -ForegroundColor White
Write-Host "  Include Empty Groups: $($Data.IncludeEmptyGroups)" -ForegroundColor White

Write-Host "`nGroup Statistics:" -ForegroundColor Cyan
Write-Host "  Total Groups in AD: $($stats.TotalGroups)" -ForegroundColor White
Write-Host "  Groups with Nested Groups: $($stats.GroupsWithNestedGroups)" -ForegroundColor White
Write-Host "  Root Groups (not nested): $($Data.GroupHierarchy.Count)" -ForegroundColor White
Write-Host "  Maximum Nesting Depth: $($stats.MaxDepthFound)" -ForegroundColor White
Write-Host "  Circular References Found: $($stats.CircularReferences)" -ForegroundColor $(if ($stats.CircularReferences -gt 0) { "Red" } else { "Green" })

# Calculate hierarchy statistics
$totalDisplayedGroups = 0
$groupsByDepth = @{}

function Count-Groups {
    param([object]$GroupData, [int]$Depth = 0)
    
    $script:totalDisplayedGroups++
    if (-not $groupsByDepth.ContainsKey($Depth)) {
        $groupsByDepth[$Depth] = 0
    }
    $groupsByDepth[$Depth]++
    
    if ($GroupData.NestedGroups) {
        foreach ($nested in $GroupData.NestedGroups) {
            Count-Groups -GroupData $nested -Depth ($Depth + 1)
        }
    }
}

foreach ($rootGroup in $Data.GroupHierarchy) {
    Count-Groups -GroupData $rootGroup
}

Write-Host "`nHierarchy Distribution:" -ForegroundColor Cyan
for ($i = 0; $i -le ($stats.MaxDepthFound); $i++) {
    if ($groupsByDepth.ContainsKey($i)) {
        $percentage = [math]::Round(($groupsByDepth[$i] / $totalDisplayedGroups) * 100, 1)
        Write-Host "  Depth $i`: $($groupsByDepth[$i]) groups ($percentage%)" -ForegroundColor White
    }
}

Write-Host "`nTop 10 Groups by Nested Count:" -ForegroundColor Cyan
$allGroupsFlat = @()

function Flatten-Groups {
    param([object]$GroupData)
    $script:allGroupsFlat += $GroupData
    if ($GroupData.NestedGroups) {
        foreach ($nested in $GroupData.NestedGroups) {
            Flatten-Groups -GroupData $nested
        }
    }
}

foreach ($rootGroup in $Data.GroupHierarchy) {
    Flatten-Groups -GroupData $rootGroup
}

$topGroups = $allGroupsFlat | Sort-Object NestedGroupCount -Descending | Select-Object -First 10
foreach ($group in $topGroups) {
    $color = if ($group.NestedGroupCount -gt 5) { "Yellow" } elseif ($group.NestedGroupCount -gt 2) { "Green" } else { "White" }
    Write-Host "  $($group.Name): $($group.NestedGroupCount) nested groups" -ForegroundColor $color
}

Write-Host "`n" + "="*60 -ForegroundColor Yellow
```

}

# Main execution

try {
if (-not (Test-Path $JsonPath)) {
Write-Error “JSON file not found: $JsonPath”
exit 1
}

```
Write-Host "Loading AD group hierarchy data..." -ForegroundColor Gray
$jsonData = Get-Content $JsonPath -Raw | ConvertFrom-Json

if ($OutputFile) {
    # Clear output file
    Set-Content -Path $OutputFile -Value "AD Group Hierarchy Report"
    "Generated: $(Get-Date)" | Add-Content -Path $OutputFile
    "Source: $JsonPath" | Add-Content -Path $OutputFile
    "`n" + "="*80 | Add-Content -Path $OutputFile
}

if ($ShowStats) {
    Show-Statistics -Data $jsonData
    if ($OutputFile) {
        "`n`nSTATISTICS (see console output for formatted version)" | Add-Content -Path $OutputFile
    }
}

# Filter by specific group if requested
$groupsToShow = if ($GroupName) {
    $filteredGroups = @()
    
    function Find-Group {
        param([object]$GroupData)
        
        if ($GroupData.Name -like "*$GroupName*" -or $GroupData.SamAccountName -like "*$GroupName*") {
            return $GroupData
        }
        
        if ($GroupData.NestedGroups) {
            foreach ($nested in $GroupData.NestedGroups) {
                $found = Find-Group -GroupData $nested
                if ($found) {
                    return $found
                }
            }
        }
        
        return $null
    }
    
    foreach ($rootGroup in $jsonData.GroupHierarchy) {
        $found = Find-Group -GroupData $rootGroup
        if ($found) {
            $filteredGroups += $found
        }
    }
    
    if ($filteredGroups.Count -eq 0) {
        Write-Warning "No groups found matching: $GroupName"
        exit 1
    }
    
    $filteredGroups
} else {
    $jsonData.GroupHierarchy
}

if ($groupsToShow.Count -eq 0) {
    Write-Warning "No groups to display"
    exit 1
}

# Display header
$header = if ($GroupName) { 
    "AD Group Hierarchy for: $GroupName" 
} else { 
    "AD Group Hierarchy (All Root Groups)" 
}

if ($OutputFile) {
    "`n$header" | Add-Content -Path $OutputFile
    "="*80 | Add-Content -Path $OutputFile
} else {
    Write-Host "`n$header" -ForegroundColor Yellow
    Write-Host ("="*80) -ForegroundColor Yellow
}

# Display hierarchy
if ($ShowPaths) {
    Write-Host "`nShowing as paths:" -ForegroundColor Gray
    foreach ($group in $groupsToShow) {
        Show-GroupPaths -GroupData $group
    }
} else {
    Write-Host "`nShowing as tree structure:" -ForegroundColor Gray
    for ($i = 0; $i -lt $groupsToShow.Count; $i++) {
        $isLast = ($i -eq ($groupsToShow.Count - 1))
        Show-GroupTree -GroupData $groupsToShow[$i] -IsLast $isLast -MaxDepth $MaxDisplayDepth
        
        if (-not $isLast) {
            if ($OutputFile) {
                "" | Add-Content -Path $OutputFile
            } else {
                Write-Host ""
            }
        }
    }
}

if ($OutputFile) {
    Write-Host "`nOutput saved to: $OutputFile" -ForegroundColor Green
}

Write-Host "`nVisualization complete!" -ForegroundColor Green
```

} catch {
Write-Error “Error displaying group hierarchy: $_”
throw
}
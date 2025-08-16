#Requires -Version 7.0
<#
.SYNOPSIS
Simple script to find Entra groups that don’t exist in Active Directory
.DESCRIPTION
Basic comparison to identify cloud-only groups for testing
#>

[CmdletBinding()]
param()

# Import modules

Import-Module (Join-Path $PSScriptRoot “....\Modules\Entra.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “....\Modules\AD.Functions.psm1”) -Force
Import-Module (Join-Path $PSScriptRoot “....\Modules\Common.Functions.psm1”) -Force

# Get configuration

$config = Get-Config -ConfigPath (Join-Path $PSScriptRoot “....\Modules\giam-config.json”) -Force -Verbose
Initialize-DataPaths -Config $config

# Setup output

$timestamp = Get-Date -Format $config.FileManagement.DateFormat
$outputPath = Join-Path $config.Paths.CSV “GIAM-UnsyncedEntraGroups_$timestamp.csv”

Write-Host “Finding Entra groups not in AD…” -ForegroundColor Cyan

try {
# Step 1: Get Entra groups
Write-Host “Collecting Entra groups…” -ForegroundColor Yellow
Connect-ToGraph -Config $config.EntraID

```
$entraGroups = @()
$nextLink = "https://graph.microsoft.com/v1.0/groups?`$select=displayName,id&`$top=999"

while ($nextLink) {
    $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink
    $entraGroups += $response.value
    $nextLink = $response.'@odata.nextLink'
    
    Write-Host "  Got $($entraGroups.Count) Entra groups so far..." -ForegroundColor Gray
}

Write-Host "Total Entra groups: $($entraGroups.Count)" -ForegroundColor Green

# Step 2: Get AD groups  
Write-Host "Collecting AD groups..." -ForegroundColor Yellow

$adGroupNames = @()
$connection = New-LDAPConnection -Config $config.ActiveDirectory

$searchRequest = New-LDAPSearchRequest `
    -SearchBase $config.ActiveDirectory.OrganizationalUnit `
    -Filter "(objectClass=group)" `
    -Attributes @("name")

$pagingControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl(1000)

do {
    $searchRequest.Controls.Clear()
    $searchRequest.Controls.Add($pagingControl)
    $response = $connection.SendRequest($searchRequest)
    
    foreach ($entry in $response.Entries) {
        if ($entry.Attributes["name"]) {
            $adGroupNames += $entry.Attributes["name"][0]
        }
    }
    
    $cookie = ($response.Controls | Where-Object { $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl] }).Cookie
    $pagingControl.Cookie = $cookie
    
    Write-Host "  Got $($adGroupNames.Count) AD groups so far..." -ForegroundColor Gray
    
} while ($null -ne $cookie -and $cookie.Length -ne 0)

$connection.Dispose()
Write-Host "Total AD groups: $($adGroupNames.Count)" -ForegroundColor Green

# Step 3: Find unsynced groups
Write-Host "Comparing groups..." -ForegroundColor Yellow

$unsyncedGroups = @()

foreach ($entraGroup in $entraGroups) {
    if ($entraGroup.displayName -notin $adGroupNames) {
        $unsyncedGroups += $entraGroup
    }
}

Write-Host "Found $($unsyncedGroups.Count) unsynced groups" -ForegroundColor Green

# Step 4: Output to CSV
if ($unsyncedGroups.Count -gt 0) {
    $csvData = $unsyncedGroups | Select-Object @{Name="GroupName";Expression={$_.displayName}}, @{Name="GroupId";Expression={$_.id}}
    $csvData | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
    
    Write-Host "Results saved to: $outputPath" -ForegroundColor Green
    
    # Show first few results
    Write-Host "`nFirst 10 unsynced groups:" -ForegroundColor Cyan
    $unsyncedGroups | Select-Object -First 10 | ForEach-Object {
        Write-Host "  - $($_.displayName)" -ForegroundColor White
    }
} else {
    Write-Host "No unsynced groups found!" -ForegroundColor Yellow
}
```

} catch {
Write-Error “Error: $_”
} finally {
if ($connection) { $connection.Dispose() }
Disconnect-MgGraph -ErrorAction SilentlyContinue
}

Write-Host “`nDone!” -ForegroundColor Green
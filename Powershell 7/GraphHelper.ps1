#region Script Variables
$script:mutex = $null
#endregion

#region Configuration
function Import-ScriptConfig {
    [CmdletBinding()]
    param (
        [string]$ConfigPath = "$PSScriptRoot\config.json"
    )
    
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found at: $ConfigPath"
    }
    
    try {
        $config = Get-Content $ConfigPath | ConvertFrom-Json
        return $config
    }
    catch {
        throw "Error reading configuration: $_"
    }
}
#endregion

#region Mutex Management
function Initialize-ScriptMutex {
    if ($null -eq $script:mutex) {
        $script:mutex = New-Object System.Threading.Mutex
    }
}
#endregion

#region Connection Functions
function Connect-ToGraph {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        [Parameter(Mandatory = $true)]
        [string]$AppID,
        [Parameter(Mandatory = $true)]
        [string]$Thumbprint
    )
    
    try {
        Connect-MgGraph -ClientId $AppID -TenantId $TenantID -CertificateThumbprint $Thumbprint -NoWelcome
        $context = Get-MgContext
        if (-not $context) {
            throw "Failed to establish Graph connection"
        }
        Write-Verbose "Successfully connected to Graph API"
        return $context
    }
    catch {
        Write-Error "Failed to connect to Graph API: $_"
        throw
    }
}

function Invoke-RetryableOperation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 2
    )
    
    $attempt = 1
    $success = $false
    while (-not $success -and $attempt -le $MaxRetries) {
        try {
            $result = & $ScriptBlock
            $success = $true
            return $result
        }
        catch {
            if ($attempt -ge $MaxRetries) {
                Write-Error "Failed to execute $Operation after $MaxRetries attempts: $_"
                throw
            }
            $delay = $RetryDelaySeconds * [Math]::Pow(2, ($attempt - 1))
            Write-Warning "$Operation failed (Attempt $attempt of $MaxRetries). Waiting $delay seconds..."
            Start-Sleep -Seconds $delay
            $attempt++
        }
    }
}
#endregion

#region Memory and Cache Management
function Get-CurrentMemoryUsage {
    try {
        $process = Get-Process -Id $pid
        return $process.WorkingSet64 / 1GB
    }
    catch {
        Write-Error "Failed to get memory usage: $_"
        return 0
    }
}

function Clear-ScriptCache {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [System.Collections.Hashtable[]]$Caches,
        [switch]$Force
    )
    
    if ($Force -or $Caches) {
        Write-Verbose "Clearing script caches..."
        foreach ($cache in $Caches) {
            if ($cache) {
                $cache.Clear()
            }
        }
        [System.GC]::Collect()
        Start-Sleep -Seconds 1
    }
}

function Initialize-CacheData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int]$MemoryThresholdGB,
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable[]]$Caches
    )
    
    try {
        Clear-ScriptCache -Force -Caches $Caches
        Write-Verbose "Caches initialized empty - will populate on demand"
    }
    catch {
        Write-Error "Error initializing cache data: $_"
        Clear-ScriptCache -Force -Caches $Caches
        throw
    }
}
#endregion

#region File Operations
function Initialize-ExportFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ExportFolder,
        [Parameter(Mandatory = $true)]
        [string]$FilePrefix,
        [Parameter(Mandatory = $true)]
        [string]$Header
    )
    
    try {
        if (-not (Test-Path $ExportFolder)) {
            New-Item -ItemType Directory -Path $ExportFolder -Force | Out-Null
            Write-Verbose "Created export folder: $ExportFolder"
        }

        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $exportPath = Join-Path $ExportFolder "${FilePrefix}_${timestamp}.csv"
        
        Set-Content -Path $exportPath -Value $Header -Encoding UTF8
        
        Write-Verbose "Initialized export file: $exportPath"
        return $exportPath
    }
    catch {
        Write-Error "Failed to initialize export file: $_"
        throw
    }
}

function Write-BatchResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Collections.Concurrent.ConcurrentBag[string]]$BatchResults,
        [Parameter(Mandatory=$true)]
        [string]$ExportPath
    )
    try {
        Initialize-ScriptMutex
        $script:mutex.WaitOne() | Out-Null
        $BatchResults | Add-Content -Path $ExportPath -Encoding UTF8
    }
    catch {
        Write-Error "Failed to write batch results: $_"
        throw
    }
    finally {
        if ($script:mutex) {
            $script:mutex.ReleaseMutex()
        }
    }
}

function Invoke-CsvPostProcessing {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceCsvPath,
        [string]$BackupFolder = $config.FileManagementConfig.Paths.Backup,
        [string]$CsvFolder = $config.FileManagementConfig.Paths.CSV
    )
    try {
        # Ensure directories exist
        @($BackupFolder, $CsvFolder) | ForEach-Object {
            if (-not (Test-Path $_)) {
                New-Item -ItemType Directory -Path $_ -Force | Out-Null
                Write-Verbose "Created directory: $_"
            }
        }

        # Get file names
        $sourceFileName = [System.IO.Path]::GetFileName($SourceCsvPath)
        $baseFileName = $sourceFileName -replace '_\d{8}-\d{6}\.csv$', '.csv'
        $destinationPath = Join-Path $CsvFolder $baseFileName

        # Create backup
        $timestamp = [datetime]::Now.ToString("yyyyMMdd-HHmmss")
        if ($config.FileManagementConfig.CompressBackups) {
            $backupZipPath = Join-Path $BackupFolder "$([System.IO.Path]::GetFileNameWithoutExtension($SourceCsvPath))_$timestamp.zip"
            Compress-Archive -Path $SourceCsvPath -DestinationPath $backupZipPath -Force
            Write-Verbose "Created compressed backup: $backupZipPath"
        }
        else {
            $backupPath = Join-Path $BackupFolder "$([System.IO.Path]::GetFileNameWithoutExtension($SourceCsvPath))_$timestamp.csv"
            Copy-Item -Path $SourceCsvPath -Destination $backupPath -Force
            Write-Verbose "Created backup: $backupPath"
        }

        # Check for existing file
        if (Test-Path $destinationPath) {
            Write-Verbose "Existing file found: $destinationPath"
            
            # Import CSVs
            $existingData = Import-Csv -Path $destinationPath
            $newData = Import-Csv -Path $SourceCsvPath

            # Important: Get headers from the source CSV file to maintain order
            $originalHeaders = (Get-Content -Path $SourceCsvPath -First 1).Split(',')
            $keyFields = $originalHeaders[0..($originalHeaders.Count-2)]
            $valueField = $originalHeaders[-1]
            
            Write-Verbose "Comparing files using keys: $($keyFields -join ', ')"
            
            # Compare files
            $existingHash = @{}
            $existingData | ForEach-Object {
                $key = ($keyFields | ForEach-Object { $_.$_ }) -join '|'
                $existingHash[$key] = $_
            }

            $mergedResults = [System.Collections.Generic.List[object]]::new()
            $updatedCount = 0
            $newCount = 0

            $newData | ForEach-Object {
                $currentRow = $_
                $key = ($keyFields | ForEach-Object { $currentRow.$_ }) -join '|'

                if ($existingHash.ContainsKey($key)) {
                    $existing = $existingHash[$key]
                    if ($existing.$valueField -ne $currentRow.$valueField) {
                        Write-Verbose "Updated value found for key: $key"
                        $mergedResults.Add($currentRow)
                        $updatedCount++
                    }
                    else {
                        $mergedResults.Add($existing)
                    }
                    $existingHash.Remove($key)
                }
                else {
                    $mergedResults.Add($currentRow)
                    $newCount++
                }
            }

            # Add remaining existing records
            $existingHash.Values | ForEach-Object {
                $mergedResults.Add($_)
            }

            if ($newCount -gt 0 -or $updatedCount -gt 0) {
                Write-Verbose "Found $newCount new records and $updatedCount updates"
                
                # Write header using original order
                Set-Content -Path $destinationPath -Value ($originalHeaders -join ',') -Encoding UTF8

                # Write data rows maintaining original header order
                $mergedResults | ForEach-Object {
                    $row = $_
                    $line = $originalHeaders | ForEach-Object { $row.$_ } | Join-String -Separator ','
                    Add-Content -Path $destinationPath -Value $line -Encoding UTF8
                }
                
                Write-Verbose "Updated existing file with merged data"
            }
            else {
                Write-Verbose "No changes detected - keeping existing file"
            }
        }
        else {
            Write-Verbose "No existing file found - moving and renaming new file"
            Move-Item -Path $SourceCsvPath -Destination $destinationPath -Force
            Write-Verbose "Created new file: $destinationPath"
        }

        # Clean up temp file after processing
        if (Test-Path $SourceCsvPath) {
            Remove-Item -Path $SourceCsvPath -Force
            Write-Verbose "Cleaned up temporary file: $SourceCsvPath"
        }
    }
    catch {
        Write-Error "Error in CSV post-processing: $_"
        throw
    }
}
#endregion

#region Graph Operations
function Get-AllGraphResults {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [int]$MemoryThresholdGB
    )
    
    if (-not $Uri.StartsWith('https://graph.microsoft.com/v1.0/')) {
        throw "Invalid Graph API URI format: $Uri"
    }
    
    $results = [System.Collections.Generic.List[object]]::new()
    $nextLink = $Uri
    $resultCount = 0
    
    while ($nextLink) {
        if ($resultCount % 1000 -eq 0) {
            $currentMemory = Get-CurrentMemoryUsage
            if ($currentMemory -gt $MemoryThresholdGB) {
                Write-Warning "Memory usage ($([math]::Round($currentMemory,2))GB) exceeding threshold."
                [System.GC]::Collect()
                Start-Sleep -Seconds 2
            }
        }
        
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink
        if ($response.value) {
            $results.AddRange($response.value)
            $resultCount += $response.value.Count
        }
        $nextLink = $response.'@odata.nextLink'
    }
    return $results
}

function Get-GraphGroup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GroupName,
        [Parameter(Mandatory = $true)]
        [int]$BatchSize
    )
    
    try {
        $groupResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$GroupName'"
        if (-not $groupResponse.value) {
            throw "Group '$GroupName' not found"
        }
        $groupId = $groupResponse.value[0].id
        return "https://graph.microsoft.com/v1.0/groups/$groupId/members?`$select=id,userPrincipalName&`$top=$BatchSize"
    }
    catch {
        Write-Error "Failed to get group: $_"
        throw
    }
}
#endregion

#region Cleanup
function Invoke-ScriptCleanup {
    if ($script:mutex) {
        $script:mutex.Dispose()
        $script:mutex = $null
    }
    [System.GC]::Collect()
}
#endregion

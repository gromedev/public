#Requires -Version 7.0
<#
.SYNOPSIS
    Identifies inactive service accounts in Active Directory.
#>

[CmdletBinding()]
param(
    [int]$InactiveDays = 90,
    [string]$OutputPath = (Get-Location).Path,
    [string]$SearchBase,
    [int]$PageSize = 500
)

#region Helper Functions
function Convert-FileTimeToDateTime {
    param ([object]$FileTime)

    try {
        if ($null -eq $FileTime) { return "NULL" }

        $fileTimeValue = if ($FileTime -is [byte[]]) {
            [BitConverter]::ToInt64($FileTime, 0)
        }
        else {
            [Int64]::Parse($FileTime.ToString())
        }

        if ($fileTimeValue -eq 0 -or
            $fileTimeValue -eq [Int64]::MaxValue -or
            $fileTimeValue -eq 9223372036854775807) {
            return "NULL"
        }

        return [DateTime]::FromFileTime($fileTimeValue).ToString(
            "yyyy-MM-dd HH:mm:ss",
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }
    catch { return "NULL" }
}

function Convert-LDAPDateTimeString {
    param ([object]$DateTimeValue)

    try {
        $dateString = if ($DateTimeValue -is [byte[]]) {
            [System.Text.Encoding]::UTF8.GetString($DateTimeValue)
        }
        else {
            $DateTimeValue.ToString()
        }

        if ($dateString -match '(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})') {
            $date = [DateTime]::ParseExact(
                $matches[1..6] -join '',
                'yyyyMMddHHmmss',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            return $date.ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
        }

        return [DateTime]::Parse($dateString).ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch { return "NULL" }
}

function Get-CSVSafeValue {
    param ([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return "" }

    $cleanValue = $Value -replace "`r`n", " " -replace "`n", " " -replace "`r", " " -replace "`t", " "
    $cleanValue = $cleanValue -replace "\s+", " "
    $cleanValue = $cleanValue.Trim()
    $cleanValue = $cleanValue -replace [char]0x00, ""
    $cleanValue = $cleanValue -replace [char]0x1A, ""
    $cleanValue = $cleanValue -replace '"', '""'

    return $cleanValue
}

function Get-ServiceAccountType {
    param ([object]$Attributes)

    $objectClasses = @()

    if ($Attributes["objectClass"]) {
        foreach ($obj in $Attributes["objectClass"]) {
            if ($obj -is [byte[]]) {
                try {
                    $stringValue = [System.Text.Encoding]::UTF8.GetString($obj)
                    $stringValue = $stringValue.Trim([char]0)
                    if (-not [string]::IsNullOrWhiteSpace($stringValue)) {
                        $objectClasses += $stringValue
                    }
                }
                catch {
                    try {
                        $stringValue = [System.Text.Encoding]::ASCII.GetString($obj)
                        $stringValue = $stringValue.Trim([char]0)
                        if (-not [string]::IsNullOrWhiteSpace($stringValue)) {
                            $objectClasses += $stringValue
                        }
                    }
                    catch { }
                }
            }
            elseif ($obj -is [string]) {
                $objectClasses += $obj.Trim()
            }
            else {
                $stringValue = $obj.ToString().Trim()
                if (-not [string]::IsNullOrWhiteSpace($stringValue)) {
                    $objectClasses += $stringValue
                }
            }
        }
    }

    if ($objectClasses -contains "msDS-GroupManagedServiceAccount") { return "gMSA" }
    if ($objectClasses -contains "msDS-ManagedServiceAccount") { return "MSA" }
    if ($objectClasses -contains "user") { return "User (with SPN)" }
    return "Unknown"
}
#endregion

try {
    Add-Type -AssemblyName System.DirectoryServices.Protocols -ErrorAction Stop

    # Resolve search base if not provided
    if (-not $SearchBase) {
        $rootDSE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://RootDSE")
        $SearchBase = $rootDSE.Properties["defaultNamingContext"][0]
        Write-Host "Auto-detected domain root: $SearchBase" -ForegroundColor Cyan
    }

    # Validate output directory
    if (-not (Test-Path $OutputPath)) {
        throw "Output directory does not exist: $OutputPath"
    }

    # Connect
    $domain = ($env:USERDNSDOMAIN -split '\.')[0]
    $identifier = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier($domain, 389)
    $connection = New-Object System.DirectoryServices.Protocols.LdapConnection($identifier)
    $connection.SessionOptions.ProtocolVersion = 3
    $connection.SessionOptions.ReferralChasing = 'None'
    $connection.Timeout = New-TimeSpan -Seconds 300

    Write-Host "Connected to LDAP server: $domain" -ForegroundColor Green

    # LDAP filter: MSAs, gMSAs, and user accounts with SPNs (excluding computer accounts)
    $ldapFilter = "(|(objectClass=msDS-ManagedServiceAccount)(objectClass=msDS-GroupManagedServiceAccount)(&(objectClass=user)(!(objectClass=computer))(servicePrincipalName=*)))"

    $attributes = @(
        "sAMAccountName",
        "distinguishedName",
        "objectClass",
        "lastLogonTimestamp",
        "userAccountControl",
        "servicePrincipalName",
        "description",
        "whenCreated",
        "pwdLastSet"
    )

    # Build search request
    $searchRequest = New-Object System.DirectoryServices.Protocols.SearchRequest
    $searchRequest.DistinguishedName = $SearchBase
    $searchRequest.Filter = $ldapFilter
    $searchRequest.Scope = [System.DirectoryServices.Protocols.SearchScope]::Subtree
    $searchRequest.Attributes.AddRange($attributes)

    Write-Host "LDAP Filter: $ldapFilter" -ForegroundColor Cyan
    Write-Host "Search Base: $SearchBase" -ForegroundColor Cyan
    Write-Host "Inactive threshold: $InactiveDays days" -ForegroundColor Cyan
    Write-Host ""

    # Setup CSV output
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $csvFileName = "ServiceAccounts_$timestamp.csv"
    $csvFilePath = Join-Path $OutputPath $csvFileName

    $csvHeader = @(
        "sAMAccountName",
        "AccountType",
        "Enabled",
        "DistinguishedName",
        "LastLogonTimestamp",
        "DaysSinceLastLogon",
        "PasswordLastSet",
        "DaysSincePasswordChange",
        "InactiveStatus",
        "WhenCreated",
        "ServicePrincipalNames",
        "Description"
    ) -join ","

    Set-Content -Path $csvFilePath -Value $csvHeader -Encoding UTF8
    Write-Host "Output file: $csvFilePath" -ForegroundColor Green
    Write-Host ""

    # Initialize processing
    $resultBuffer = [System.Collections.Generic.List[string]]::new()
    $processedCount = 0
    $pageNumber = 0
    $bufferLimit = 500
    $now = Get-Date

    $summary = @{
        TotalAccounts = 0
        MSA           = 0
        GMSA          = 0
        UserWithSPN   = 0
        Enabled       = 0
        Disabled      = 0
        Active        = 0
        Inactive      = 0
        NeverLoggedOn = 0
    }

    $pagingControl = New-Object System.DirectoryServices.Protocols.PageResultRequestControl($PageSize)

    do {
        $pageNumber++
        Write-Host "Processing page $pageNumber (page size: $PageSize)..." -ForegroundColor Gray

        $searchRequest.Controls.Clear()
        $searchRequest.Controls.Add($pagingControl)
        $response = $connection.SendRequest($searchRequest) -as [System.DirectoryServices.Protocols.SearchResponse]

        if ($null -eq $response -or $response.Entries.Count -eq 0) {
            Write-Host "No more results found." -ForegroundColor Gray
            break
        }

        # Get cookie for next page
        $cookie = ($response.Controls | Where-Object {
            $_ -is [System.DirectoryServices.Protocols.PageResultResponseControl]
        }).Cookie
        $pagingControl.Cookie = $cookie

        foreach ($entry in $response.Entries) {
            $attrs = $entry.Attributes

            # sAMAccountName
            $samAccountName = if ($attrs["sAMAccountName"]) {
                $attrs["sAMAccountName"][0]
            } else { "" }

            # Account type
            $accountType = Get-ServiceAccountType -Attributes $attrs

            # Distinguished name
            $distinguishedName = Get-CSVSafeValue -Value $(
                if ($attrs["distinguishedName"]) {
                    $attrs["distinguishedName"][0]
                } else { "" }
            )

            # UAC flags
            $enabled = 0
            if ($attrs["userAccountControl"]) {
                $uac = $attrs["userAccountControl"][0]
                $enabled = if ($uac -band 0x2) { 0 } else { 1 }
            }

            # lastLogonTimestamp
            $lastLogonRaw = if ($attrs["lastLogonTimestamp"]) {
                Convert-FileTimeToDateTime -FileTime $attrs["lastLogonTimestamp"][0]
            } else { "NULL" }

            # Days since last logon
            $daysSinceLogon = "N/A"
            if ($lastLogonRaw -ne "NULL") {
                try {
                    $logonDate = [DateTime]::ParseExact(
                        $lastLogonRaw,
                        "yyyy-MM-dd HH:mm:ss",
                        [System.Globalization.CultureInfo]::InvariantCulture
                    )
                    $daysSinceLogon = [Math]::Floor(($now - $logonDate).TotalDays)
                }
                catch { $daysSinceLogon = "N/A" }
            }

            # pwdLastSet
            $pwdLastSetRaw = if ($attrs["pwdLastSet"]) {
                $val = Convert-FileTimeToDateTime -FileTime $attrs["pwdLastSet"][0]
                if ($val -eq "NULL") { "" } else { $val }
            } else { "" }

            # Days since password change
            $daysSincePwdChange = "N/A"
            if ($pwdLastSetRaw -ne "" -and $pwdLastSetRaw -ne "NULL") {
                try {
                    $pwdDate = [DateTime]::ParseExact(
                        $pwdLastSetRaw,
                        "yyyy-MM-dd HH:mm:ss",
                        [System.Globalization.CultureInfo]::InvariantCulture
                    )
                    $daysSincePwdChange = [Math]::Floor(($now - $pwdDate).TotalDays)
                }
                catch { $daysSincePwdChange = "N/A" }
            }

            # Classify inactive status
            $inactiveStatus = if ($enabled -eq 0) {
                "Disabled"
            }
            elseif ($lastLogonRaw -eq "NULL") {
                "Never Logged On"
            }
            elseif ($daysSinceLogon -ne "N/A" -and $daysSinceLogon -ge $InactiveDays) {
                "Inactive"
            }
            else {
                "Active"
            }

            # whenCreated
            $whenCreated = if ($attrs["whenCreated"]) {
                Convert-LDAPDateTimeString -DateTimeValue $attrs["whenCreated"][0]
            } else { "" }

            # servicePrincipalName (multi-valued, semicolon-delimited)
            $spns = ""
            if ($attrs["servicePrincipalName"]) {
                $spnList = @()
                foreach ($spn in $attrs["servicePrincipalName"]) {
                    if ($spn -is [byte[]]) {
                        try {
                            $spnList += [System.Text.Encoding]::UTF8.GetString($spn).Trim([char]0)
                        }
                        catch { }
                    }
                    elseif ($spn -is [string]) {
                        $spnList += $spn
                    }
                    else {
                        $spnList += $spn.ToString()
                    }
                }
                $spns = Get-CSVSafeValue -Value ($spnList -join "; ")
            }

            # description
            $description = Get-CSVSafeValue -Value $(
                if ($attrs["description"]) {
                    $attrs["description"][0]
                } else { "" }
            )

            # Update summary
            $summary.TotalAccounts++
            switch ($accountType) {
                "MSA"             { $summary.MSA++ }
                "gMSA"            { $summary.GMSA++ }
                "User (with SPN)" { $summary.UserWithSPN++ }
            }
            if ($enabled -eq 1) { $summary.Enabled++ } else { $summary.Disabled++ }
            switch ($inactiveStatus) {
                "Active"          { $summary.Active++ }
                "Inactive"        { $summary.Inactive++ }
                "Never Logged On" { $summary.NeverLoggedOn++ }
            }

            # Format CSV line
            $csvFields = @(
                $samAccountName,
                $accountType,
                $enabled,
                $distinguishedName,
                $lastLogonRaw,
                $daysSinceLogon,
                $pwdLastSetRaw,
                $daysSincePwdChange,
                $inactiveStatus,
                $whenCreated,
                $spns,
                $description
            )
            $line = ($csvFields | ForEach-Object { "`"$_`"" }) -join ","
            $resultBuffer.Add($line)

            if ($resultBuffer.Count -ge $bufferLimit) {
                $resultBuffer | Add-Content -Path $csvFilePath -Encoding UTF8
                $resultBuffer.Clear()
            }

            $processedCount++
        }

        Write-Host "Completed page $pageNumber. Total processed: $processedCount" -ForegroundColor Gray

    } while ($null -ne $cookie -and $cookie.Length -ne 0)

    # Flush remaining buffer
    if ($resultBuffer.Count -gt 0) {
        $resultBuffer | Add-Content -Path $csvFilePath -Encoding UTF8
        $resultBuffer.Clear()
    }

    # Summary
    Write-Host "Report saved to: $csvFilePath" -ForegroundColor Green
}
catch {
    Write-Host "Error collecting service accounts: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    throw
}
finally {
    if ($connection) { $connection.Dispose() }
    if ($resultBuffer) { $resultBuffer.Clear() }
    [System.GC]::Collect()
}

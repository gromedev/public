# Install SQLite module for PowerShell 7 compatibility
# Install-Module -Name SQLite -Scope CurrentUser -Force

# Configuration
$databasePath = "C:\temp\database.db"  # Ensure this directory exists and is writable
$defaultClientId = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
$defaultResource = "https://graph.microsoft.com"
$defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

# Helper Functions
function Get-UserAgent {
    $query = "SELECT value FROM settings WHERE setting = 'user_agent'"
    $result = Invoke-SQLiteCommand -Connection $databasePath -Query $query
    if ($result) {
        return $result.value
    }
    return $defaultUserAgent
}

function Is-ValidUUID {
    param ($val)
    try {
        [System.Guid]::Parse($val) | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-TenantId {
    param ($tenantDomain)
    $headers = @{ "User-Agent" = Get-UserAgent }
    $response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantDomain/.well-known/openid-configuration" -Headers $headers -Method Get
    $tenantId = $response.authorization_endpoint.Split('/')[3]
    return $tenantId
}

function Initialize-Database {
    $createAccessTokens = @"
CREATE TABLE IF NOT EXISTS accesstokens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    stored_at TEXT,
    issued_at TEXT,
    expires_at TEXT,
    description TEXT,
    user TEXT,
    resource TEXT,
    accesstoken TEXT
)
"@
    $createRefreshTokens = @"
CREATE TABLE IF NOT EXISTS refreshtokens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    stored_at TEXT,
    description TEXT,
    user TEXT,
    tenant_id TEXT,
    resource TEXT,
    foci INTEGER,
    refreshtoken TEXT
)
"@
    $createDeviceCodes = @"
CREATE TABLE IF NOT EXISTS devicecodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    generated_at INTEGER,
    expires_at INTEGER,
    user_code TEXT,
    device_code TEXT,
    interval INTEGER,
    client_id TEXT,
    status TEXT,
    last_poll INTEGER
)
"@
    $createSettings = @"
CREATE TABLE IF NOT EXISTS settings (
    setting TEXT UNIQUE,
    value TEXT
)
"@
    $insertSchemaVersion = "INSERT OR IGNORE INTO settings (setting, value) VALUES ('schema_version', '4')"

    Invoke-SQLiteCommand -Connection $databasePath -Query $createAccessTokens
    Invoke-SQLiteCommand -Connection $databasePath -Query $createRefreshTokens
    Invoke-SQLiteCommand -Connection $databasePath -Query $createDeviceCodes
    Invoke-SQLiteCommand -Connection $databasePath -Query $createSettings
    Invoke-SQLiteCommand -Connection $databasePath -Query $insertSchemaVersion
}

function Save-AccessToken {
    param ($accessToken, $description)

    # Decode JWT (basic parsing since PowerShell lacks pyjwt)
    $parts = $accessToken.Split('.')
    $payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($parts[1] + ('=' * (4 - ($parts[1].Length % 4)))))
    $decoded = ConvertFrom-Json $payload

    $user = "unknown"
    if ($decoded.idtyp -eq "user") {
        $user = if ($decoded.unique_name) { $decoded.unique_name } elseif ($decoded.upn) { $decoded.upn } else { "unknown" }
    } elseif ($decoded.idtyp -eq "app") {
        $user = if ($decoded.app_displayname) { $decoded.app_displayname } elseif ($decoded.appid) { $decoded.appid } else { "unknown" }
    } else {
        $user = if ($decoded.unique_name) { $decoded.unique_name } `
                elseif ($decoded.upn) { $decoded.upn } `
                elseif ($decoded.app_displayname) { $decoded.app_displayname } `
                elseif ($decoded.oid) { $decoded.oid } `
                else { "unknown" }
    }

    $storedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $issuedAt = if ($decoded.iat) { (Get-Date "1970-01-01").AddSeconds($decoded.iat).ToString("yyyy-MM-dd HH:mm:ss") } else { "unknown" }
    $expiresAt = if ($decoded.exp) { (Get-Date "1970-01-01").AddSeconds($decoded.exp).ToString("yyyy-MM-dd HH:mm:ss") } else { "unknown" }
    $resource = if ($decoded.aud) { $decoded.aud } else { "unknown" }

    $query = @"
INSERT INTO accesstokens (stored_at, issued_at, expires_at, description, user, resource, accesstoken)
VALUES (@storedAt, @issuedAt, @expiresAt, @description, @user, @resource, @accesstoken)
"@
    $params = @{
        "storedAt" = $storedAt
        "issuedAt" = $issuedAt
        "expiresAt" = $expiresAt
        "description" = $description
        "user" = $user
        "resource" = $resource
        "accesstoken" = $accessToken
    }
    Invoke-SQLiteCommand -Connection $databasePath -Query $query -Parameters $params
}

function Save-RefreshToken {
    param ($refreshToken, $description, $user, $tenant, $resource, $foci)

    $fociInt = if ($foci) { 1 } else { 0 }
    $tenantId = if (Is-ValidUUID ($tenant -replace '[^\w-]','')) { ($tenant -replace '[^\w-]','') } else { Get-TenantId $tenant }

    $query = @"
INSERT INTO refreshtokens (stored_at, description, user, tenant_id, resource, foci, refreshtoken)
VALUES (@storedAt, @description, @user, @tenantId, @resource, @foci, @refreshtoken)
"@
    $params = @{
        "storedAt" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        "description" = $description
        "user" = $user
        "tenantId" = $tenantId
        "resource" = $resource
        "foci" = $fociInt
        "refreshtoken" = $refreshToken
    }
    Invoke-SQLiteCommand -Connection $databasePath -Query $query -Parameters $params
}

function Generate-DeviceCode {
    param (
        $resource = $defaultResource,
        $clientId = $defaultClientId,
        [switch]$ngcmfa
    )

    $body = @{
        resource  = $resource
        client_id = $clientId
    }
    if ($ngcmfa) {
        $body["amr_values"] = "ngcmfa"
    }

    $url = "https://login.microsoftonline.com/common/oauth2/devicecode?api-version=1.0"
    $headers = @{ "User-Agent" = Get-UserAgent }

    $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body

    $query = @"
INSERT INTO devicecodes (generated_at, expires_at, user_code, device_code, interval, client_id, status, last_poll)
VALUES (@generatedAt, @expiresAt, @userCode, @deviceCode, @interval, @clientId, @status, @lastPoll)
"@
    $params = @{
        "generatedAt" = [int](Get-Date -UFormat %s)
        "expiresAt" = [int](Get-Date -UFormat %s) + [int]$response.expires_in
        "userCode" = $response.user_code
        "deviceCode" = $response.device_code
        "interval" = [int]$response.interval
        "clientId" = $clientId
        "status" = "CREATED"
        "lastPoll" = 0
    }
    Invoke-SQLiteCommand -Connection $databasePath -Query $query -Parameters $params

    return $response.device_code
}

function Poll-DeviceCodes {
    while ($true) {
        $query = "SELECT * FROM devicecodes WHERE status IN ('CREATED', 'POLLING')"
        $rows = Invoke-SQLiteCommand -Connection $databasePath -Query $query | Sort-Object last_poll

        if (-not $rows) {
            break
        }

        foreach ($row in $rows) {
            $currentTime = [int](Get-Date -UFormat %s)
            if ($currentTime -gt $row.expires_at) {
                $query = "UPDATE devicecodes SET status = @status WHERE device_code = @deviceCode"
                $params = @{
                    "status" = "EXPIRED"
                    "deviceCode" = $row.device_code
                }
                Invoke-SQLiteCommand -Connection $databasePath -Query $query -Parameters $params
                continue
            }

            $nextPoll = $row.last_poll + $row.interval
            if ($currentTime -lt $nextPoll) {
                Start-Sleep -Seconds ($nextPoll - $currentTime)
            }

            if ($row.status -eq "CREATED") {
                $query = "UPDATE devicecodes SET status = @status WHERE device_code = @deviceCode"
                $params = @{
                    "status" = "POLLING"
                    "deviceCode" = $row.device_code
                }
                Invoke-SQLiteCommand -Connection $databasePath -Query $query -Parameters $params
            }

            $body = @{
                client_id  = $row.client_id
                grant_type = "urn:ietf:params:oauth:grant-type:device_code"
                code       = $row.device_code
            }
            $url = "https://login.microsoftonline.com/Common/oauth2/token?api-version=1.0"
            $headers = @{ "User-Agent" = Get-UserAgent }

            try {
                $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
                $query = "UPDATE devicecodes SET last_poll = @lastPoll WHERE device_code = @deviceCode"
                $params = @{
                    "lastPoll" = [int](Get-Date -UFormat %s)
                    "deviceCode" = $row.device_code
                }
                Invoke-SQLiteCommand -Connection $databasePath -Query $query -Parameters $params

                if ($response.access_token) {
                    $accessToken = $response.access_token
                    $userCode = $row.user_code
                    Save-AccessToken -accessToken $accessToken -description "Created using device code auth ($userCode)"

                    # Decode access token
                    $parts = $accessToken.Split('.')
                    $payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($parts[1] + ('=' * (4 - ($parts[1].Length % 4)))))
                    $decoded = ConvertFrom-Json $payload

                    $user = "unknown"
                    if ($decoded.idtyp -eq "user") {
                        $user = if ($decoded.unique_name) { $decoded.unique_name } elseif ($decoded.upn) { $decoded.upn } else { "unknown" }
                    } elseif ($decoded.idtyp -eq "app") {
                        $user = if ($decoded.app_displayname) { $decoded.app_displayname } elseif ($decoded.appid) { $decoded.appid } else { "unknown" }
                    }

                    Save-RefreshToken -refreshToken $response.refresh_token `
                                     -description "Created using device code auth ($userCode)" `
                                     -user $user `
                                     -tenant ($decoded.tid ? $decoded.tid : "unknown") `
                                     -resource ($response.resource ? $response.resource : "unknown") `
                                     -foci ([int]($response.foci ? $response.foci : 0))

                    $query = "UPDATE devicecodes SET status = @status WHERE device_code = @deviceCode"
                    $params = @{
                        "status" = "SUCCESS"
                        "deviceCode" = $row.device_code
                    }
                    Invoke-SQLiteCommand -Connection $databasePath -Query $query -Parameters $params
                }
            } catch {
                # Handle errors (e.g., authorization_pending)
                $query = "UPDATE devicecodes SET last_poll = @lastPoll WHERE device_code = @deviceCode"
                $params = @{
                    "lastPoll" = [int](Get-Date -UFormat %s)
                    "deviceCode" = $row.device_code
                }
                Invoke-SQLiteCommand -Connection $databasePath -Query $query -Parameters $params
            }
        }
    }
}

function Start-DeviceCodePolling {
    $job = Start-Job -ScriptBlock {
        param ($dbPath)
        # Re-import SQLite in the job context
        Import-Module SQLite

        # Define Get-UserAgent
        function Get-UserAgent {
            $query = "SELECT value FROM settings WHERE setting = 'user_agent'"
            $result = Invoke-SQLiteCommand -Connection $dbPath -Query $query
            if ($result) {
                return $result.value
            }
            return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
        }

        # Define Save-AccessToken
        function Save-AccessToken {
            param ($accessToken, $description)

            # Decode JWT (basic parsing since PowerShell lacks pyjwt)
            $parts = $accessToken.Split('.')
            $payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($parts[1] + ('=' * (4 - ($parts[1].Length % 4)))))
            $decoded = ConvertFrom-Json $payload

            $user = "unknown"
            if ($decoded.idtyp -eq "user") {
                $user = if ($decoded.unique_name) { $decoded.unique_name } elseif ($decoded.upn) { $decoded.upn } else { "unknown" }
            } elseif ($decoded.idtyp -eq "app") {
                $user = if ($decoded.app_displayname) { $decoded.app_displayname } elseif ($decoded.appid) { $decoded.appid } else { "unknown" }
            } else {
                $user = if ($decoded.unique_name) { $decoded.unique_name } `
                        elseif ($decoded.upn) { $decoded.upn } `
                        elseif ($decoded.app_displayname) { $decoded.app_displayname } `
                        elseif ($decoded.oid) { $decoded.oid } `
                        else { "unknown" }
            }

            $storedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $issuedAt = if ($decoded.iat) { (Get-Date "1970-01-01").AddSeconds($decoded.iat).ToString("yyyy-MM-dd HH:mm:ss") } else { "unknown" }
            $expiresAt = if ($decoded.exp) { (Get-Date "1970-01-01").AddSeconds($decoded.exp).ToString("yyyy-MM-dd HH:mm:ss") } else { "unknown" }
            $resource = if ($decoded.aud) { $decoded.aud } else { "unknown" }

            $query = @"
INSERT INTO accesstokens (stored_at, issued_at, expires_at, description, user, resource, accesstoken)
VALUES (@storedAt, @issuedAt, @expiresAt, @description, @user, @resource, @accesstoken)
"@
            $params = @{
                "storedAt" = $storedAt
                "issuedAt" = $issuedAt
                "expiresAt" = $expiresAt
                "description" = $description
                "user" = $user
                "resource" = $resource
                "accesstoken" = $accessToken
            }
            Invoke-SQLiteCommand -Connection $dbPath -Query $query -Parameters $params
        }

        # Define Save-RefreshToken
        function Save-RefreshToken {
            param ($refreshToken, $description, $user, $tenant, $resource, $foci)

            function Is-ValidUUID {
                param ($val)
                try {
                    [System.Guid]::Parse($val) | Out-Null
                    return $true
                } catch {
                    return $false
                }
            }

            function Get-TenantId {
                param ($tenantDomain)
                $headers = @{ "User-Agent" = Get-UserAgent }
                $response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantDomain/.well-known/openid-configuration" -Headers $headers -Method Get
                $tenantId = $response.authorization_endpoint.Split('/')[3]
                return $tenantId
            }

            $fociInt = if ($foci) { 1 } else { 0 }
            $tenantId = if (Is-ValidUUID ($tenant -replace '[^\w-]','')) { ($tenant -replace '[^\w-]','') } else { Get-TenantId $tenant }

            $query = @"
INSERT INTO refreshtokens (stored_at, description, user, tenant_id, resource, foci, refreshtoken)
VALUES (@storedAt, @description, @user, @tenantId, @resource, @foci, @refreshtoken)
"@
            $params = @{
                "storedAt" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                "description" = $description
                "user" = $user
                "tenantId" = $tenantId
                "resource" = $resource
                "foci" = $fociInt
                "refreshtoken" = $refreshToken
            }
            Invoke-SQLiteCommand -Connection $dbPath -Query $query -Parameters $params
        }

        # Define Poll-DeviceCodes
        function Poll-DeviceCodes {
            while ($true) {
                $query = "SELECT * FROM devicecodes WHERE status IN ('CREATED', 'POLLING')"
                $rows = Invoke-SQLiteCommand -Connection $dbPath -Query $query | Sort-Object last_poll

                if (-not $rows) {
                    break
                }

                foreach ($row in $rows) {
                    $currentTime = [int](Get-Date -UFormat %s)
                    if ($currentTime -gt $row.expires_at) {
                        $query = "UPDATE devicecodes SET status = @status WHERE device_code = @deviceCode"
                        $params = @{
                            "status" = "EXPIRED"
                            "deviceCode" = $row.device_code
                        }
                        Invoke-SQLiteCommand -Connection $dbPath -Query $query -Parameters $params
                        continue
                    }

                    $nextPoll = $row.last_poll + $row.interval
                    if ($currentTime -lt $nextPoll) {
                        Start-Sleep -Seconds ($nextPoll - $currentTime)
                    }

                    if ($row.status -eq "CREATED") {
                        $query = "UPDATE devicecodes SET status = @status WHERE device_code = @deviceCode"
                        $params = @{
                            "status" = "POLLING"
                            "deviceCode" = $row.device_code
                        }
                        Invoke-SQLiteCommand -Connection $dbPath -Query $query -Parameters $params
                    }

                    $body = @{
                        client_id  = $row.client_id
                        grant_type = "urn:ietf:params:oauth:grant-type:device_code"
                        code       = $row.device_code
                    }
                    $url = "https://login.microsoftonline.com/Common/oauth2/token?api-version=1.0"
                    $headers = @{ "User-Agent" = Get-UserAgent }

                    try {
                        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
                        $query = "UPDATE devicecodes SET last_poll = @lastPoll WHERE device_code = @deviceCode"
                        $params = @{
                            "lastPoll" = [int](Get-Date -UFormat %s)
                            "deviceCode" = $row.device_code
                        }
                        Invoke-SQLiteCommand -Connection $dbPath -Query $query -Parameters $params

                        if ($response.access_token) {
                            $accessToken = $response.access_token
                            $userCode = $row.user_code
                            Save-AccessToken -accessToken $accessToken -description "Created using device code auth ($userCode)"

                            # Decode access token
                            $parts = $accessToken.Split('.')
                            $payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($parts[1] + ('=' * (4 - ($parts[1].Length % 4)))))
                            $decoded = ConvertFrom-Json $payload

                            $user = "unknown"
                            if ($decoded.idtyp -eq "user") {
                                $user = if ($decoded.unique_name) { $decoded.unique_name } elseif ($decoded.upn) { $decoded.upn } else { "unknown" }
                            } elseif ($decoded.idtyp -eq "app") {
                                $user = if ($decoded.app_displayname) { $decoded.app_displayname } elseif ($decoded.appid) { $decoded.appid } else { "unknown" }
                            }

                            Save-RefreshToken -refreshToken $response.refresh_token `
                                             -description "Created using device code auth ($userCode)" `
                                             -user $user `
                                             -tenant ($decoded.tid ? $decoded.tid : "unknown") `
                                             -resource ($response.resource ? $response.resource : "unknown") `
                                             -foci ([int]($response.foci ? $response.foci : 0))

                            $query = "UPDATE devicecodes SET status = @status WHERE device_code = @deviceCode"
                            $params = @{
                                "status" = "SUCCESS"
                                "deviceCode" = $row.device_code
                            }
                            Invoke-SQLiteCommand -Connection $dbPath -Query $query -Parameters $params
                        }
                    } catch {
                        # Handle errors (e.g., authorization_pending)
                        $query = "UPDATE devicecodes SET last_poll = @lastPoll WHERE device_code = @deviceCode"
                        $params = @{
                            "lastPoll" = [int](Get-Date -UFormat %s)
                            "deviceCode" = $row.device_code
                        }
                        Invoke-SQLiteCommand -Connection $dbPath -Query $query -Parameters $params
                    }
                }
            }
        }
        Poll-DeviceCodes
    } -ArgumentList $databasePath
    return "Started device code polling job with ID: $($job.Id)"
}

function Invoke-DeviceCodeFlow {
    param (
        $resource = $defaultResource,
        $clientId = $defaultClientId,
        [switch]$ngcmfa
    )

    $deviceCode = Generate-DeviceCode -resource $resource -clientId $clientId -ngcmfa:$ngcmfa
    $query = "SELECT user_code FROM devicecodes WHERE device_code = @deviceCode"
    $params = @{
        "deviceCode" = $deviceCode
    }
    $userCode = (Invoke-SQLiteCommand -Connection $databasePath -Query $query -Parameters $params).user_code

    Start-DeviceCodePolling
    return $userCode
}

function Refresh-ToAccessToken {
    param (
        $refreshTokenId,
        $clientId = $defaultClientId,
        $resource = "defined_in_token",
        $scope = "",
        [switch]$storeRefreshToken,
        $apiVersion = 1
    )

    $query = "SELECT refreshtoken, tenant_id, resource FROM refreshtokens WHERE id = @id"
    $params = @{
        "id" = $refreshTokenId
    }
    $tokenData = Invoke-SQLiteCommand -Connection $databasePath -Query $query -Parameters $params
    if (-not $tokenData) {
        throw "Refresh token with ID $refreshTokenId not found."
    }

    $refreshToken = $tokenData.refreshtoken
    $tenantId = $tokenData.tenant_id
    $resource = if ($resource -eq "defined_in_token") { $tokenData.resource } else { $resource }

    $body = @{
        client_id     = $clientId
        grant_type    = "refresh_token"
        refresh_token = $refreshToken
    }
    $url = "https://login.microsoftonline.com/$tenantId"
    if ($apiVersion -eq 1) {
        $body["resource"] = $resource
        $url += "/oauth2/token?api-version=1.0"
    } elseif ($apiVersion -eq 2) {
        $body["scope"] = $scope
        $url += "/oauth2/v2.0/token"
    }

    $headers = @{ "User-Agent" = Get-UserAgent }

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
        $accessToken = $response.access_token
        Save-AccessToken -accessToken $accessToken -description "Created using refresh token $refreshTokenId"

        $query = "SELECT id FROM accesstokens WHERE accesstoken = @accesstoken"
        $params = @{
            "accesstoken" = $accessToken
        }
        $accessTokenId = (Invoke-SQLiteCommand -Connection $databasePath -Query $query -Parameters $params).id

        if ($storeRefreshToken) {
            $parts = $accessToken.Split('.')
            $payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($parts[1] + ('=' * (4 - ($parts[1].Length % 4)))))
            $decoded = ConvertFrom-Json $payload

            $user = "unknown"
            if ($decoded.idtyp -eq "user") {
                $user = if ($decoded.unique_name) { $decoded.unique_name } elseif ($decoded.upn) { $decoded.upn } else { "unknown" }
            } elseif ($decoded.idtyp -eq "app") {
                $user = if ($decoded.app_displayname) { $decoded.app_displayname } elseif ($decoded.appid) { $decoded.appid } else { "unknown" }
            }

            Save-RefreshToken -refreshToken $response.refresh_token `
                             -description "Created using refresh token $refreshTokenId" `
                             -user $user `
                             -tenant $tenantId `
                             -resource ($response.resource ? $response.resource : "unknown") `
                             -foci ([int]($response.foci ? $response.foci : 0))
        }

        return $accessTokenId
    } catch {
        $errorResponse = $_.ErrorDetails.Message | ConvertFrom-Json
        return "[$($errorResponse.error)] $($errorResponse.error_description)"
    }
}

# Main Execution
try {
    # Initialize database if it doesn't exist
    if (-not (Test-Path $databasePath)) {
        Write-Host "Initializing new database at $databasePath"
        Initialize-Database
    }

    # Example: Start device code flow
    $userCode = Invoke-DeviceCodeFlow -resource $defaultResource -clientId $defaultClientId
    Write-Host "User Code: $userCode"
    Write-Host "Please visit https://microsoft.com/devicelogin and enter the code to authenticate."

    # Example: Use a refresh token (replace '1' with actual refresh token ID)
    # $accessTokenId = Refresh-ToAccessToken -refreshTokenId 1 -storeRefreshToken
    # Write-Host "Access Token ID: $accessTokenId"
} catch {
    Write-Error "An error occurred: $_"
}
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Check Zscaler detection vectors and stealth configuration status

.DESCRIPTION
    This script checks:
    - Zscaler SSL inspection capability
    - DNS over HTTPS configuration
    - Tailscale DERP mode status
    - Active Tailscale connections
    - DNS cache for Tailscale queries
    - Network configuration
    - Routing table for exit nodes
    - CGNAT range conflicts
    - Zscaler Client Connector presence
    - Detection risk assessment

.NOTES
    Run as Administrator for complete information
#>

Write-Host "`n=== ZSCALER DETECTION RISK ASSESSMENT ===" -ForegroundColor Cyan
Write-Host "Analyzing your configuration for Zscaler detection vectors...`n" -ForegroundColor Yellow

$detectionScore = 0
$maxScore = 15  # Updated to account for exit node and CGNAT checks
$findings = @()
$hasDirectConnection = $false
$tailscaleDefaultRoute = $false
$hasClientConnector = $false

# ============================================================================
# CHECK 1: Zscaler Certificate (SSL Inspection Capability)
# ============================================================================
Write-Host "[1/10] Checking for Zscaler SSL Inspection..." -ForegroundColor Green

try {
    $zscalerCerts = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object {
        $_.Subject -like "*Zscaler*" -or $_.Issuer -like "*Zscaler*"
    }
    
    if ($zscalerCerts) {
        Write-Host "  Status: ZSCALER ROOT CA FOUND" -ForegroundColor Red
        Write-Host "  Details: SSL inspection is ENABLED on this machine" -ForegroundColor Yellow
        $zscalerCerts | ForEach-Object {
            Write-Host "    Certificate: $($_.Subject)" -ForegroundColor Gray
            Write-Host "    Thumbprint: $($_.Thumbprint)" -ForegroundColor Gray
        }
        $detectionScore += 1
        $findings += "Zscaler SSL inspection is enabled (can intercept HTTPS)"
    } else {
        Write-Host "  Status: NO ZSCALER CERTIFICATE FOUND" -ForegroundColor Green
        Write-Host "  Details: SSL inspection not detected" -ForegroundColor Gray
        $findings += "No Zscaler SSL inspection detected"
    }
} catch {
    Write-Warning "  Could not check certificates: $_"
}

Write-Host ""

# ============================================================================
# CHECK 2: DNS Configuration & DNS over HTTPS
# ============================================================================
Write-Host "[2/10] Checking DNS Configuration..." -ForegroundColor Green

try {
    $activeAdapter = Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and 
        $_.InterfaceDescription -notlike "*Tailscale*" -and 
        $_.InterfaceDescription -notlike "*Loopback*"
    } | Select-Object -First 1
    
    if ($activeAdapter) {
        Write-Host "  Active Adapter: $($activeAdapter.Name)" -ForegroundColor Cyan
        
        # Get DNS servers
        $dnsServers = Get-DnsClientServerAddress -InterfaceAlias $activeAdapter.Name -AddressFamily IPv4
        Write-Host "  DNS Servers: $($dnsServers.ServerAddresses -join ', ')" -ForegroundColor Gray
        
        # Check if using corporate DNS (common patterns)
        $usingCorporateDNS = $false
        foreach ($dns in $dnsServers.ServerAddresses) {
            if ($dns -match "^10\." -or $dns -match "^172\.(1[6-9]|2[0-9]|3[0-1])\." -or $dns -match "^192\.168\.") {
                $usingCorporateDNS = $true
                break
            }
        }
        
        if ($usingCorporateDNS) {
            Write-Host "  Warning: Using CORPORATE DNS (queries visible)" -ForegroundColor Red
            $detectionScore += 2
            $findings += "Using corporate DNS - all queries visible to Zscaler"
        } elseif ($dnsServers.ServerAddresses -contains "1.1.1.1" -or $dnsServers.ServerAddresses -contains "8.8.8.8") {
            Write-Host "  Status: Using PUBLIC DNS (Cloudflare/Google)" -ForegroundColor Yellow
        }
        
        # Check DoH
        $dohServers = Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue
        if ($dohServers) {
            Write-Host "  DNS over HTTPS: ENABLED" -ForegroundColor Green
            $dohServers | ForEach-Object {
                Write-Host "    Server: $($_.ServerAddress) - $($_.DohTemplate)" -ForegroundColor Gray
            }
            $findings += "DNS over HTTPS enabled - queries encrypted"
        } else {
            Write-Host "  DNS over HTTPS: NOT CONFIGURED" -ForegroundColor Red
            $detectionScore += 3
            $findings += "DNS queries NOT encrypted - Zscaler can see all lookups"
        }
    }
} catch {
    Write-Warning "  Could not check DNS configuration: $_"
}

Write-Host ""

# ============================================================================
# CHECK 3: DNS Cache for Tailscale Queries
# ============================================================================
Write-Host "[3/10] Checking DNS Cache for Tailscale Queries..." -ForegroundColor Green

try {
    $dnsCache = Get-DnsClientCache -ErrorAction SilentlyContinue | Where-Object {
        $_.Entry -like "*tailscale*"
    }
    
    if ($dnsCache) {
        Write-Host "  Status: TAILSCALE DNS ENTRIES FOUND IN CACHE" -ForegroundColor Red
        Write-Host "  Warning: Recent queries to Tailscale domains detected" -ForegroundColor Yellow
        $dnsCache | Select-Object -First 5 | ForEach-Object {
            Write-Host "    $($_.Entry) → $($_.Data)" -ForegroundColor Gray
        }
        $findings += "Tailscale DNS queries in cache (may be logged by Zscaler)"
    } else {
        Write-Host "  Status: No Tailscale entries in DNS cache" -ForegroundColor Green
        $findings += "No Tailscale DNS queries in cache"
    }
} catch {
    Write-Host "  Could not check DNS cache" -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# CHECK 4: Firewall Rules (DERP-Only Mode)
# ============================================================================
Write-Host "[4/10] Checking Firewall Rules (DERP-Only Mode)..." -ForegroundColor Green

$expectedRules = @(
    "Block Tailscale Direct UDP",
    "Block Tailscale Direct UDP Inbound",
    "Block Tailscale Remote UDP"
)

$activeRules = 0
foreach ($ruleName in $expectedRules) {
    $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($rule -and $rule.Enabled -eq $true) {
        $activeRules++
    }
}

if ($activeRules -eq 3) {
    Write-Host "  Status: DERP-ONLY MODE ACTIVE (all 3 rules present)" -ForegroundColor Green
    Write-Host "  Details: Tailscale forced to use TCP/443 relays" -ForegroundColor Gray
    $findings += "DERP-only mode active - using TCP/443 (looks like HTTPS)"
} elseif ($activeRules -gt 0) {
    Write-Host "  Status: PARTIAL CONFIGURATION ($activeRules/3 rules)" -ForegroundColor Yellow
    Write-Host "  Warning: Some direct connections may still occur" -ForegroundColor Yellow
    $detectionScore += 1
    $findings += "Incomplete DERP configuration - some UDP may leak"
} else {
    Write-Host "  Status: NORMAL MODE (no firewall rules)" -ForegroundColor Red
    Write-Host "  Warning: Using direct UDP connections (WireGuard signatures visible)" -ForegroundColor Red
    $detectionScore += 3
    $findings += "Direct UDP mode - WireGuard protocol easily detected by DPI"
}

Write-Host ""

# ============================================================================
# CHECK 5: Tailscale Service Status
# ============================================================================
Write-Host "[5/10] Checking Tailscale Service..." -ForegroundColor Green

$tailscalePath = "C:\Program Files\Tailscale\tailscale.exe"
if (Test-Path $tailscalePath) {
    try {
        $status = & $tailscalePath status 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Status: RUNNING" -ForegroundColor Green
            
            # Check for connection types
            if ($status -match "relay") {
                Write-Host "  Connections: Using DERP relays (GOOD)" -ForegroundColor Green
            }
            
            if ($status -match "direct \d+\.\d+\.\d+\.\d+") {
                Write-Host "  Warning: DIRECT CONNECTIONS DETECTED" -ForegroundColor Red
                Write-Host "  Details: WireGuard UDP traffic visible to DPI" -ForegroundColor Yellow
                $detectionScore += 2
                $findings += "Direct UDP connections active - detectable by Zscaler DPI"
            }
        } else {
            Write-Host "  Status: NOT RUNNING" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  Status: Could not check Tailscale" -ForegroundColor Gray
    }
} else {
    Write-Host "  Status: Tailscale not installed" -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# CHECK 6: Active Network Connections to Tailscale
# ============================================================================
Write-Host "[6/10] Checking Active Network Connections..." -ForegroundColor Green

try {
    # Check UDP endpoints on 41641 - but only flag if there are ACTIVE remote connections
    $udpEndpoints = Get-NetUDPEndpoint -LocalPort 41641 -ErrorAction SilentlyContinue
    $hasActiveUDP = $false
    
    if ($udpEndpoints) {
        # Check if any have remote addresses (actual connections vs just listening)
        foreach ($endpoint in $udpEndpoints) {
            if ($endpoint.RemoteAddress -and 
                $endpoint.RemoteAddress -ne "::" -and 
                $endpoint.RemoteAddress -ne "0.0.0.0" -and
                $endpoint.RemoteAddress -ne "*") {
                $hasActiveUDP = $true
                break
            }
        }
    }
    
    # Better check: Parse Tailscale status JSON for actual connection types
    $tailscalePath = "C:\Program Files\Tailscale\tailscale.exe"
    $hasDirectConnection = $false
    
    if (Test-Path $tailscalePath) {
        try {
            $statusJson = & $tailscalePath status --json 2>$null | ConvertFrom-Json
            
            # Check if any peer has a direct connection (non-empty CurAddr)
            if ($statusJson.Peer) {
                foreach ($peer in $statusJson.Peer.PSObject.Properties) {
                    if ($peer.Value.CurAddr -and $peer.Value.CurAddr -ne "") {
                        $hasDirectConnection = $true
                        Write-Host "  Warning: Direct connection to $($peer.Value.HostName)" -ForegroundColor Yellow
                        Write-Host "    Address: $($peer.Value.CurAddr)" -ForegroundColor Gray
                    }
                }
            }
            
            # If no direct connections found, confirm DERP usage
            if (-not $hasDirectConnection) {
                $derpCount = 0
                foreach ($peer in $statusJson.Peer.PSObject.Properties) {
                    if ($peer.Value.Relay -and $peer.Value.Relay -ne "") {
                        $derpCount++
                    }
                }
                
                if ($derpCount -gt 0) {
                    Write-Host "  Status: All connections via DERP relays ($derpCount peers)" -ForegroundColor Green
                    Write-Host "  Details: No direct UDP connections detected" -ForegroundColor Gray
                    $findings += "All Tailscale connections via DERP - no direct UDP"
                } else {
                    Write-Host "  Status: No active Tailscale connections" -ForegroundColor Gray
                }
            } else {
                Write-Host "  Warning: DIRECT UDP CONNECTIONS DETECTED" -ForegroundColor Red
                $detectionScore += 2
                $findings += "Direct UDP connections active - detectable by Zscaler DPI"
            }
            
        } catch {
            # Fallback to basic UDP check if JSON parsing fails
            if ($hasActiveUDP) {
                Write-Host "  Warning: UDP port 41641 has active connections" -ForegroundColor Yellow
                $detectionScore += 1
                $findings += "Port 41641 active - possible direct connections"
            } else {
                Write-Host "  Status: UDP port 41641 listening only (no active connections)" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "  Status: Tailscale not installed" -ForegroundColor Gray
    }
    
    # Check for HTTPS connections (DERP relays)
    $httpsConnections = Get-NetTCPConnection -RemotePort 443 -State Established -ErrorAction SilentlyContinue | 
        Measure-Object | Select-Object -ExpandProperty Count
    
    if ($httpsConnections -gt 0) {
        Write-Host "  Info: $httpsConnections active HTTPS connections (port 443)" -ForegroundColor Cyan
        Write-Host "  Details: Normal for DERP relay mode" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Could not check network connections" -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# CHECK 7: Tailscale Network Interface
# ============================================================================
Write-Host "[7/10] Checking Tailscale Network Interface..." -ForegroundColor Green

try {
    $tailscaleAdapter = Get-NetAdapter | Where-Object {
        $_.InterfaceDescription -like "*Tailscale*"
    }
    
    if ($tailscaleAdapter) {
        Write-Host "  Status: Tailscale adapter found - $($tailscaleAdapter.Name)" -ForegroundColor Cyan
        Write-Host "  State: $($tailscaleAdapter.Status)" -ForegroundColor Gray
        
        # Get IP configuration
        $ipConfig = Get-NetIPAddress -InterfaceAlias $tailscaleAdapter.Name -ErrorAction SilentlyContinue | 
            Where-Object { $_.AddressFamily -eq "IPv4" }
        
        if ($ipConfig) {
            Write-Host "  Tailscale IP: $($ipConfig.IPAddress)" -ForegroundColor Gray
            
            # Check if using CGNAT range (100.x.y.z)
            if ($ipConfig.IPAddress -match "^100\.") {
                Write-Host "  Info: Using CGNAT range (100.x.y.z) - standard Tailscale" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "  Status: No Tailscale adapter found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  Could not check Tailscale adapter" -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# CHECK 8: Recent Network Activity Patterns
# ============================================================================
Write-Host "[8/10] Analyzing Network Activity Patterns..." -ForegroundColor Green

try {
    # Check for high-volume connections
    $allConnections = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue
    $totalConnections = ($allConnections | Measure-Object).Count
    
    Write-Host "  Active TCP Connections: $totalConnections" -ForegroundColor Cyan
    
    if ($totalConnections -gt 200) {
        Write-Host "  Warning: High connection count (may trigger pattern analysis)" -ForegroundColor Yellow
    } else {
        Write-Host "  Status: Normal connection count" -ForegroundColor Green
    }
} catch {
    Write-Host "  Could not analyze network patterns" -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# CHECK 9: Proxy/PAC Configuration
# ============================================================================
Write-Host "[9/10] Checking Proxy Configuration..." -ForegroundColor Green

try {
    $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
    
    if ($proxySettings.ProxyEnable -eq 1) {
        Write-Host "  Status: PROXY ENABLED" -ForegroundColor Yellow
        Write-Host "  Proxy Server: $($proxySettings.ProxyServer)" -ForegroundColor Gray
        
        if ($proxySettings.ProxyServer -like "*zscaler*") {
            Write-Host "  Detection: ZSCALER PROXY DETECTED" -ForegroundColor Red
            $findings += "Zscaler proxy explicitly configured"
        }
    } else {
        Write-Host "  Status: No proxy configured" -ForegroundColor Green
    }
    
    # Check for PAC file
    if ($proxySettings.AutoConfigURL) {
        Write-Host "  PAC File: $($proxySettings.AutoConfigURL)" -ForegroundColor Cyan
        if ($proxySettings.AutoConfigURL -like "*zscaler*") {
            Write-Host "  Detection: ZSCALER PAC FILE DETECTED" -ForegroundColor Red
            $findings += "Zscaler PAC file configured"
        }
    }
} catch {
    Write-Host "  Could not check proxy configuration" -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# CHECK 10: Zscaler Client Connector Detection (Comprehensive)
# ============================================================================
Write-Host "[10/10] Checking for Zscaler Client Connector..." -ForegroundColor Green

$hasZscalerClient = $false

try {
    # Check for Zscaler processes
    $zscalerProcesses = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like "*zscaler*" -or 
        $_.ProcessName -like "*ZSA*" -or
        $_.ProcessName -like "*ZEN*" -or
        $_.ProcessName -eq "ZSATunnel" -or
        $_.ProcessName -eq "ZSAService"
    }
    
    if ($zscalerProcesses) {
        Write-Host "  ZSCALER CLIENT CONNECTOR DETECTED" -ForegroundColor Red
        $zscalerProcesses | ForEach-Object {
            Write-Host "    Process: $($_.ProcessName) (PID: $($_.Id))" -ForegroundColor Yellow
        }
        $hasZscalerClient = $true
        $findings += "Zscaler Client Connector running - endpoint monitoring active"
    }
    
    # Check for Zscaler services
    $zscalerServices = Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -like "*zscaler*" -or 
        $_.Name -like "*ZSA*" -or
        $_.Name -like "*ZEN*"
    }
    
    if ($zscalerServices) {
        if (-not $hasZscalerClient) {
            Write-Host "  ZSCALER SERVICES DETECTED" -ForegroundColor Red
        }
        $zscalerServices | ForEach-Object {
            Write-Host "    Service: $($_.DisplayName) - $($_.Status)" -ForegroundColor Yellow
        }
        $hasZscalerClient = $true
        if ($findings -notcontains "Zscaler Client Connector running - endpoint monitoring active") {
            $findings += "Zscaler services installed - endpoint monitoring capable"
        }
    }
    
    # Check for Zscaler network adapters
    $zscalerAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceDescription -like "*zscaler*" -or 
        $_.InterfaceDescription -like "*ZEN*" -or
        $_.Name -like "*ZSA*"
    }
    
    if ($zscalerAdapters) {
        if (-not $hasZscalerClient) {
            Write-Host "  ZSCALER NETWORK ADAPTER DETECTED" -ForegroundColor Red
        }
        $zscalerAdapters | ForEach-Object {
            Write-Host "    Adapter: $($_.Name) - $($_.InterfaceDescription)" -ForegroundColor Yellow
        }
        $hasZscalerClient = $true
    }
    
    if (-not $hasZscalerClient) {
        Write-Host "  Status: No Zscaler Client Connector detected on this device" -ForegroundColor Green
        $findings += "No Zscaler Client Connector - endpoint monitoring not present"
    }
} catch {
    Write-Host "  Could not check for Zscaler Client Connector" -ForegroundColor Gray
}

Write-Host ""

# ============================================================================
# CHECK 11: Routing Table Analysis (Exit Node / Full Tunnel Detection)
# ============================================================================
Write-Host "[11/12] Checking Routing Table for VPN Detection Vectors..." -ForegroundColor Green

try {
    # Check for default route
    $defaultRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
    
    $tailscaleDefaultRoute = $defaultRoutes | Where-Object {
        $_.InterfaceAlias -like "*Tailscale*"
    }
    
    if ($tailscaleDefaultRoute) {
        Write-Host "  WARNING: DEFAULT ROUTE POINTS TO TAILSCALE" -ForegroundColor Red
        Write-Host "    This indicates EXIT NODE / FULL TUNNEL mode" -ForegroundColor Yellow
        Write-Host "    Zscaler Client Connector WILL detect this!" -ForegroundColor Yellow
        $detectionScore += 5
        $findings += "Tailscale exit node active - easily detected by Client Connector"
        $tailscaleDefaultRoute = $true
    } else {
        Write-Host "  Status: Default route is normal (not Tailscale)" -ForegroundColor Green
        $findings += "No exit node - split tunnel only (harder to detect)"
        $tailscaleDefaultRoute = $false
    }
    
    # Show actual default route
    $actualDefault = $defaultRoutes | Select-Object -First 1
    if ($actualDefault) {
        Write-Host "  Default Route: $($actualDefault.NextHop) via $($actualDefault.InterfaceAlias)" -ForegroundColor Gray
    }
    
    # Check Tailscale-specific routes
    $tailscaleRoutes = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceAlias -like "*Tailscale*" -and $_.DestinationPrefix -ne "0.0.0.0/0"
    }
    
    if ($tailscaleRoutes) {
        $routeCount = ($tailscaleRoutes | Measure-Object).Count
        Write-Host "  Info: $routeCount Tailscale-specific routes (split tunnel)" -ForegroundColor Cyan
    }
    
} catch {
    Write-Host "  Could not analyze routing table" -ForegroundColor Gray
    $tailscaleDefaultRoute = $false
}

Write-Host ""

# ============================================================================
# CHECK 12: CGNAT Range Conflict Detection
# ============================================================================
Write-Host "[12/12] Checking for CGNAT Range Conflicts..." -ForegroundColor Green

$cgnatConflict = $false

try {
    # Check for 100.x.y.z addresses NOT on Tailscale adapter
    $cgnatAddresses = Get-NetIPAddress -ErrorAction SilentlyContinue | Where-Object {
        $_.IPAddress -match "^100\." -and
        $_.InterfaceAlias -notlike "*Tailscale*"
    }
    
    if ($cgnatAddresses) {
        Write-Host "  WARNING: CGNAT RANGE CONFLICT DETECTED" -ForegroundColor Yellow
        Write-Host "  Non-Tailscale adapters using 100.x.y.z range:" -ForegroundColor Yellow
        $cgnatAddresses | ForEach-Object {
            Write-Host "    $($_.IPAddress) on $($_.InterfaceAlias)" -ForegroundColor Gray
            if ($_.InterfaceAlias -like "*zscaler*" -or $_.InterfaceAlias -like "*ZPA*") {
                Write-Host "      ^ This is a Zscaler adapter - CONFLICT!" -ForegroundColor Red
                $detectionScore += 2
                $findings += "CGNAT range conflict with Zscaler - may trigger detection"
                $cgnatConflict = $true
            }
        }
    } else {
        Write-Host "  Status: No CGNAT range conflicts detected" -ForegroundColor Green
        $cgnatConflict = $false
    }
    
    # Show Tailscale's CGNAT address
    $tailscaleIP = Get-NetIPAddress -ErrorAction SilentlyContinue | Where-Object {
        $_.IPAddress -match "^100\." -and
        $_.InterfaceAlias -like "*Tailscale*"
    } | Select-Object -First 1
    
    if ($tailscaleIP) {
        Write-Host "  Tailscale IP: $($tailscaleIP.IPAddress)" -ForegroundColor Cyan
    }
    
} catch {
    Write-Host "  Could not check for CGNAT conflicts" -ForegroundColor Gray
    $cgnatConflict = $false
}

Write-Host ""

# ============================================================================
# FINAL RISK ASSESSMENT
# ============================================================================
Write-Host "=== DETECTION RISK ASSESSMENT ===" -ForegroundColor Cyan
Write-Host ""

# Determine if Client Connector is present
$hasClientConnector = $findings -match "Zscaler Client Connector" -or $findings -match "Zscaler services"

# Calculate risk level
$riskPercentage = [math]::Round(($detectionScore / $maxScore) * 100)
$riskLevel = if ($riskPercentage -lt 20) { "VERY LOW" }
            elseif ($riskPercentage -lt 40) { "LOW" }
            elseif ($riskPercentage -lt 60) { "MEDIUM" }
            elseif ($riskPercentage -lt 80) { "HIGH" }
            else { "VERY HIGH" }

$riskColor = if ($riskPercentage -lt 20) { "Green" }
            elseif ($riskPercentage -lt 40) { "Green" }
            elseif ($riskPercentage -lt 60) { "Yellow" }
            elseif ($riskPercentage -lt 80) { "Red" }
            else { "Red" }

Write-Host "Detection Risk Score: $detectionScore / $maxScore ($riskPercentage%)" -ForegroundColor $riskColor
Write-Host "Risk Level: $riskLevel" -ForegroundColor $riskColor
Write-Host ""

# Detection type analysis
if ($hasClientConnector) {
    Write-Host "DETECTION TYPE: Client Connector + Network-Level" -ForegroundColor Yellow
    Write-Host "  Zscaler Client Connector is installed on this device" -ForegroundColor Yellow
    Write-Host "  Can monitor: processes, routing table, network adapters" -ForegroundColor Gray
} else {
    Write-Host "DETECTION TYPE: Network-Level Only" -ForegroundColor Green
    Write-Host "  No Zscaler Client Connector detected on this device" -ForegroundColor Green
    Write-Host "  Only network traffic is monitored (via ZIA)" -ForegroundColor Gray
}
Write-Host ""

# Display findings
Write-Host "Key Findings:" -ForegroundColor Yellow
if ($findings.Count -eq 0) {
    Write-Host "  No significant findings" -ForegroundColor Green
} else {
    $findings | ForEach-Object {
        if ($_ -like "*NOT*" -or $_ -like "*No*" -or $_ -like "*DERP*" -or $_ -like "*encrypted*") {
            Write-Host "  [+] $_" -ForegroundColor Green
        } else {
            Write-Host "  [-] $_" -ForegroundColor Red
        }
    }
}

Write-Host ""

# Recommendations
Write-Host "=== RECOMMENDATIONS ===" -ForegroundColor Cyan
Write-Host ""

if ($detectionScore -eq 0) {
    Write-Host "EXCELLENT! Your configuration is optimal for stealth." -ForegroundColor Green
    Write-Host "  - Continue using Tailscale as configured" -ForegroundColor White
    Write-Host "  - Avoid excessive data transfers" -ForegroundColor White
    Write-Host "  - Use during normal business hours" -ForegroundColor White
} elseif ($detectionScore -le 3) {
    Write-Host "GOOD! Minor issues detected, but risk is low." -ForegroundColor Green
    if (-not (Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue)) {
        Write-Host "  ACTION: Enable DNS over HTTPS to hide queries" -ForegroundColor Yellow
        Write-Host "    Run: .\Setup-TailscaleDERPOnly-Enhanced.ps1" -ForegroundColor Gray
    }
    if ($hasClientConnector -and -not $tailscaleDefaultRoute) {
        Write-Host "  NOTE: Client Connector detected, but you're using split tunnel" -ForegroundColor Cyan
        Write-Host "        This is much harder to detect than full tunnel" -ForegroundColor Cyan
    }
} elseif ($detectionScore -le 6) {
    Write-Host "MODERATE RISK! Several detection vectors present." -ForegroundColor Yellow
    Write-Host "  PRIORITY ACTIONS:" -ForegroundColor Red
    
    if ($tailscaleDefaultRoute) {
        Write-Host "    1. URGENT: Disable Tailscale exit node immediately!" -ForegroundColor Red
        Write-Host "       Exit nodes create full tunnel = easily detected" -ForegroundColor White
        Write-Host "       Run: tailscale set --exit-node=" -ForegroundColor Gray
    }
    
    if (-not (Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue)) {
        Write-Host "    2. Enable DNS over HTTPS immediately" -ForegroundColor White
    }
    
    if ((Get-NetFirewallRule -DisplayName "Block Tailscale Direct UDP" -ErrorAction SilentlyContinue) -eq $null) {
        Write-Host "    3. Enable DERP-only mode (force TCP/443)" -ForegroundColor White
    }
    
    if ($hasClientConnector) {
        Write-Host "  NOTE: Client Connector is monitoring this device" -ForegroundColor Yellow
        Write-Host "        Consider using a VM without Client Connector instead" -ForegroundColor Yellow
    }
    
    Write-Host "    Run: .\Setup-TailscaleDERPOnly-Enhanced.ps1" -ForegroundColor Gray
} else {
    Write-Host "HIGH RISK! Multiple detection vectors active." -ForegroundColor Red
    Write-Host "  URGENT ACTIONS REQUIRED:" -ForegroundColor Red
    
    if ($tailscaleDefaultRoute) {
        Write-Host "    1. CRITICAL: Disable exit node NOW!" -ForegroundColor Red
        Write-Host "       Command: tailscale set --exit-node=" -ForegroundColor White
    }
    
    Write-Host "    2. Run setup script immediately:" -ForegroundColor White
    Write-Host "       .\Setup-TailscaleDERPOnly-Enhanced.ps1" -ForegroundColor Gray
    
    if ($hasClientConnector) {
        Write-Host "    3. RECOMMENDED: Use Tailscale on a separate device/VM" -ForegroundColor White
        Write-Host "       Client Connector cannot monitor separate devices" -ForegroundColor Gray
    } else {
        Write-Host "    3. Consider using cellular hotspot instead" -ForegroundColor White
    }
    
    Write-Host "    4. Limit Tailscale usage to non-sensitive times" -ForegroundColor White
}

Write-Host ""

# Client Connector specific guidance
if ($hasClientConnector) {
    Write-Host "=== CLIENT CONNECTOR MITIGATION ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Zscaler Client Connector is installed. Additional precautions:" -ForegroundColor Yellow
    Write-Host "  - NEVER use exit nodes (creates detectable default route)" -ForegroundColor White
    Write-Host "  - Keep split tunnel only (specific 100.x.y.z routes)" -ForegroundColor White
    Write-Host "  - Consider using Tailscale on a VM in bridged mode" -ForegroundColor White
    Write-Host "  - Or use a separate physical device without Client Connector" -ForegroundColor White
    Write-Host ""
}
Write-Host "=== STEALTH CHECKLIST ===" -ForegroundColor Cyan
Write-Host ""

$checklist = @(
    @{Item = "DNS over HTTPS enabled"; Status = (Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue) -ne $null},
    @{Item = "DERP-only mode active (3 firewall rules)"; Status = $activeRules -eq 3},
    @{Item = "No direct UDP connections (verified via Tailscale status)"; Status = -not $hasDirectConnection},
    @{Item = "No Tailscale DNS in cache"; Status = -not $dnsCache},
    @{Item = "Using public DNS (not corporate)"; Status = -not $usingCorporateDNS},
    @{Item = "No exit node / full tunnel active"; Status = -not $tailscaleDefaultRoute},
    @{Item = "No CGNAT range conflicts"; Status = -not $cgnatConflict},
    @{Item = "No Zscaler Client Connector on this device"; Status = -not $hasClientConnector}
)

foreach ($item in $checklist) {
    $symbol = if ($item.Status) { "[✓]" } else { "[✗]" }
    $color = if ($item.Status) { "Green" } else { "Red" }
    Write-Host "$symbol $($item.Item)" -ForegroundColor $color
}

Write-Host ""
Write-Host "=== VERIFICATION METHOD ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Connection Type Verification:" -ForegroundColor Yellow
Write-Host "  The script checks Tailscale's status JSON for 'CurAddr' field" -ForegroundColor White
Write-Host "  - Empty CurAddr = Using DERP relay (GOOD)" -ForegroundColor Green
Write-Host "  - Non-empty CurAddr = Direct UDP connection (BAD)" -ForegroundColor Red
Write-Host ""
Write-Host "Note: UDP port 41641 may be listening (normal), but that doesn't" -ForegroundColor Gray
Write-Host "      mean it's being used. The firewall blocks actual traffic." -ForegroundColor Gray
Write-Host ""
Write-Host "Full report complete. Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

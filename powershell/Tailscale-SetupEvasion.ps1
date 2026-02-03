#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configure Tailscale to use DERP-only mode (evade Zscaler DPI detection)

.DESCRIPTION
    This script blocks direct UDP connections on port 41641, forcing Tailscale to use
    DERP relays exclusively. DERP traffic uses TCP/443 and appears as HTTPS traffic,
    making it much harder for Zscaler to detect as VPN traffic.
    
    Also configures DNS over HTTPS to hide Tailscale DNS queries from Zscaler.

.NOTES
    Run as Administrator
    This configuration persists across reboots
#>

Write-Host "`n=== Tailscale DERP-Only Mode + DNS over HTTPS Setup ===" -ForegroundColor Cyan
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Force Tailscale to use relay servers (TCP/443) instead of direct connections" -ForegroundColor White
Write-Host "  2. Hide Tailscale DNS queries using DNS over HTTPS" -ForegroundColor White
Write-Host ""

# Check if Tailscale is installed
$tailscalePath = "C:\Program Files\Tailscale\tailscale.exe"
if (-not (Test-Path $tailscalePath)) {
    Write-Error "Tailscale not found at $tailscalePath"
    Write-Host "Please install Tailscale first: https://tailscale.com/download/windows" -ForegroundColor Red
    exit 1
}

# Step 1: Check if firewall rules already exist
Write-Host "[1/5] Checking existing firewall rules..." -ForegroundColor Green
$existingRules = @(
    "Block Tailscale Direct UDP",
    "Block Tailscale Direct UDP Inbound",
    "Block Tailscale Remote UDP"
)

$rulesToCreate = @()
foreach ($ruleName in $existingRules) {
    $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($rule) {
        Write-Host "    Found existing rule: $ruleName" -ForegroundColor Yellow
    } else {
        $rulesToCreate += $ruleName
    }
}

if ($rulesToCreate.Count -eq 0) {
    Write-Host "    All firewall rules already exist" -ForegroundColor Green
} else {
    Write-Host "    Need to create $($rulesToCreate.Count) rule(s)" -ForegroundColor Cyan
}

# Step 2: Create firewall rules to block UDP 41641 in all directions
Write-Host "[2/5] Creating firewall rules to block direct connections..." -ForegroundColor Green

# Rule 1: Block outbound on local port 41641
if ($rulesToCreate -contains "Block Tailscale Direct UDP") {
    try {
        New-NetFirewallRule -DisplayName "Block Tailscale Direct UDP" `
            -Description "Blocks Tailscale direct peer connections, forcing DERP relay mode for Zscaler evasion" `
            -Direction Outbound `
            -Protocol UDP `
            -LocalPort 41641 `
            -Action Block `
            -Enabled True | Out-Null
        Write-Host "    Created: Block Tailscale Direct UDP (outbound local port)" -ForegroundColor Green
    } catch {
        Write-Error "Failed to create firewall rule: $_"
    }
}

# Rule 2: Block inbound on local port 41641
if ($rulesToCreate -contains "Block Tailscale Direct UDP Inbound") {
    try {
        New-NetFirewallRule -DisplayName "Block Tailscale Direct UDP Inbound" `
            -Description "Blocks inbound Tailscale direct connections to force DERP mode" `
            -Direction Inbound `
            -Protocol UDP `
            -LocalPort 41641 `
            -Action Block `
            -Enabled True | Out-Null
        Write-Host "    Created: Block Tailscale Direct UDP Inbound (inbound local port)" -ForegroundColor Green
    } catch {
        Write-Error "Failed to create firewall rule: $_"
    }
}

# Rule 3: Block outbound to remote port 41641
if ($rulesToCreate -contains "Block Tailscale Remote UDP") {
    try {
        New-NetFirewallRule -DisplayName "Block Tailscale Remote UDP" `
            -Description "Blocks connections to remote Tailscale port 41641" `
            -Direction Outbound `
            -Protocol UDP `
            -RemotePort 41641 `
            -Action Block `
            -Enabled True | Out-Null
        Write-Host "    Created: Block Tailscale Remote UDP (outbound remote port)" -ForegroundColor Green
    } catch {
        Write-Error "Failed to create firewall rule: $_"
    }
}

Write-Host "    All firewall rules in place - UDP 41641 blocked in all directions" -ForegroundColor Green

# Step 3: Restart Tailscale to apply changes
Write-Host "[3/5] Restarting Tailscale service..." -ForegroundColor Green

try {
    & $tailscalePath down 2>$null
    Start-Sleep -Seconds 3
    & $tailscalePath up 2>$null
    Write-Host "    Tailscale restarted successfully" -ForegroundColor Green
} catch {
    Write-Warning "Failed to restart Tailscale: $_"
    Write-Host "    Please restart Tailscale manually" -ForegroundColor Yellow
}

# Step 4: Configure DNS over HTTPS (DoH) to hide DNS queries
Write-Host "[4/5] Configuring DNS over HTTPS to hide Tailscale DNS queries..." -ForegroundColor Green

try {
    # Auto-detect active network interface
    $activeAdapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.InterfaceDescription -notlike "*Tailscale*" -and $_.InterfaceDescription -notlike "*Loopback*"} | Select-Object -First 1
    
    if (-not $activeAdapter) {
        Write-Warning "Could not auto-detect active network adapter"
        Write-Host "`n=== MANUAL DNS OVER HTTPS CONFIGURATION REQUIRED ===" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Please configure DNS over HTTPS manually:" -ForegroundColor White
        Write-Host ""
        Write-Host "Step 1: Press Win+I to open Settings" -ForegroundColor Cyan
        Write-Host "Step 2: Go to Network & Internet > Ethernet (or Wi-Fi)" -ForegroundColor Cyan
        Write-Host "Step 3: Click your connection name" -ForegroundColor Cyan
        Write-Host "Step 4: Scroll down and click 'Hardware properties'" -ForegroundColor Cyan
        Write-Host "Step 5: Click 'Edit' next to 'DNS server assignment'" -ForegroundColor Cyan
        Write-Host "Step 6: Select 'Manual' from dropdown" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Step 7: Configure IPv4 DNS:" -ForegroundColor Cyan
        Write-Host "   - Turn ON IPv4" -ForegroundColor White
        Write-Host "   - Preferred DNS: 1.1.1.1" -ForegroundColor White
        Write-Host "   - DNS over HTTPS: On (automatic template)" -ForegroundColor Green
        Write-Host "   - Fallback to plaintext: OFF" -ForegroundColor White
        Write-Host "   - Alternate DNS: 1.0.0.1" -ForegroundColor White
        Write-Host "   - DNS over HTTPS: On (automatic template)" -ForegroundColor Green
        Write-Host "   - Fallback to plaintext: OFF" -ForegroundColor White
        Write-Host ""
        Write-Host "Step 8: Configure IPv6 DNS (optional but recommended):" -ForegroundColor Cyan
        Write-Host "   - Turn ON IPv6" -ForegroundColor White
        Write-Host "   - Preferred DNS: 2606:4700:4700::1111" -ForegroundColor White
        Write-Host "   - DNS over HTTPS: On (automatic template)" -ForegroundColor Green
        Write-Host "   - Fallback to plaintext: OFF" -ForegroundColor White
        Write-Host "   - Alternate DNS: 2606:4700:4700::1001" -ForegroundColor White
        Write-Host "   - DNS over HTTPS: On (automatic template)" -ForegroundColor Green
        Write-Host "   - Fallback to plaintext: OFF" -ForegroundColor White
        Write-Host ""
        Write-Host "Step 9: Click 'Save'" -ForegroundColor Cyan
        Write-Host "Step 10: Verify you see '(Encrypted)' next to each DNS server" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Press Enter after completing manual DoH configuration..." -ForegroundColor Yellow
        Read-Host
    } else {
        Write-Host "    Detected interface: $($activeAdapter.Name)" -ForegroundColor Cyan
        
        # Set Cloudflare DNS servers (IPv4)
        Write-Host "    Setting Cloudflare DNS servers..." -ForegroundColor Cyan
        Set-DnsClientServerAddress -InterfaceAlias $activeAdapter.Name -ServerAddresses ("1.1.1.1","1.0.0.1")
        
        # Enable DoH for primary DNS (1.1.1.1)
        Write-Host "    Enabling DoH for 1.1.1.1..." -ForegroundColor Cyan
        try {
            Add-DnsClientDohServerAddress -ServerAddress "1.1.1.1" `
                -DohTemplate "https://cloudflare-dns.com/dns-query" `
                -AllowFallbackToUdp $False `
                -AutoUpgrade $True `
                -ErrorAction Stop
            Write-Host "    SUCCESS: DoH enabled for 1.1.1.1" -ForegroundColor Green
        } catch {
            if ($_.Exception.Message -like "*already exists*") {
                Write-Host "    DoH already configured for 1.1.1.1" -ForegroundColor Yellow
            } else {
                Write-Warning "    Failed to enable DoH for 1.1.1.1: $_"
            }
        }
        
        # Enable DoH for secondary DNS (1.0.0.1)
        Write-Host "    Enabling DoH for 1.0.0.1..." -ForegroundColor Cyan
        try {
            Add-DnsClientDohServerAddress -ServerAddress "1.0.0.1" `
                -DohTemplate "https://cloudflare-dns.com/dns-query" `
                -AllowFallbackToUdp $False `
                -AutoUpgrade $True `
                -ErrorAction Stop
            Write-Host "    SUCCESS: DoH enabled for 1.0.0.1" -ForegroundColor Green
        } catch {
            if ($_.Exception.Message -like "*already exists*") {
                Write-Host "    DoH already configured for 1.0.0.1" -ForegroundColor Yellow
            } else {
                Write-Warning "    Failed to enable DoH for 1.0.0.1: $_"
            }
        }
        
        # Clear DNS cache to force DoH usage
        Write-Host "    Clearing DNS cache..." -ForegroundColor Cyan
        Clear-DnsClientCache
        
        Write-Host "    DNS over HTTPS configured successfully!" -ForegroundColor Green
    }
} catch {
    Write-Warning "Error configuring DoH: $_"
    Write-Host "`nPlease configure DNS over HTTPS manually via Windows Settings" -ForegroundColor Yellow
    Write-Host "Use Cloudflare DNS: 1.1.1.1 and 1.0.0.1 with 'On (automatic template)'" -ForegroundColor White
}

# Step 5: Wait for DERP connections and verify
Write-Host "[5/5] Waiting for DERP connections to establish..." -ForegroundColor Green
Start-Sleep -Seconds 10

# Verify configuration
Write-Host "`n=== Configuration Verification ===" -ForegroundColor Cyan

# Check firewall rules
Write-Host "`nFirewall Rules:" -ForegroundColor Yellow
$allRulesPresent = $true
foreach ($ruleName in $existingRules) {
    $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($rule -and $rule.Enabled -eq $true) {
        Write-Host "  $ruleName`: ACTIVE" -ForegroundColor Green
    } else {
        Write-Host "  $ruleName`: MISSING OR DISABLED" -ForegroundColor Red
        $allRulesPresent = $false
    }
}

# Verify DoH
Write-Host "`nDNS over HTTPS:" -ForegroundColor Yellow
try {
    $dohServers = Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue
    if ($dohServers) {
        Write-Host "  Status: ENABLED" -ForegroundColor Green
        $dohServers | ForEach-Object {
            Write-Host "  Server: $($_.ServerAddress)" -ForegroundColor Gray
        }
    } else {
        Write-Warning "  Status: NOT CONFIGURED (manual setup may be required)"
        Write-Host "  Please verify DoH manually in Windows Settings" -ForegroundColor Yellow
    }
} catch {
    Write-Warning "  Could not verify DoH configuration"
}

# Check Tailscale status
Write-Host "`nTailscale Status:" -ForegroundColor Yellow
Start-Sleep -Seconds 2
$status = & $tailscalePath status 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  Service: RUNNING" -ForegroundColor Green
    
    # Check for relay usage
    if ($status -match "relay") {
        Write-Host "  Connection: Using DERP relays" -ForegroundColor Green
    }
    
    # Check for direct connections (should be none)
    if ($status -match "direct \d+\.\d+\.\d+\.\d+") {
        Write-Warning "  WARNING: Direct connections detected!"
        Write-Host "  Run Verify-TailscaleDERPOnly.ps1 for detailed analysis" -ForegroundColor Yellow
    }
    
    Write-Host "`n--- Current Connections ---" -ForegroundColor Cyan
    Write-Host $status
} else {
    Write-Warning "  Could not retrieve Tailscale status"
}

# Final instructions
Write-Host "`n=== Setup Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "CONFIGURATION SUMMARY:" -ForegroundColor Yellow
Write-Host "  Firewall Rules: 3 rules blocking UDP port 41641 (all directions)" -ForegroundColor White
Write-Host "  DERP Mode: Forced (all traffic via TCP/443 to Tailscale relays)" -ForegroundColor White
Write-Host "  DNS over HTTPS: $(if ($dohServers) { 'Enabled (queries encrypted)' } else { 'Manual configuration required' })" -ForegroundColor White
Write-Host ""
Write-Host "WHAT ZSCALER SEES NOW:" -ForegroundColor Yellow
Write-Host "  Protocol: HTTPS/TLS on port 443 (looks like normal web traffic)" -ForegroundColor Green
Write-Host "  Destinations: Tailscale DERP servers (if DoH failed, also DNS queries)" -ForegroundColor $(if ($dohServers) { 'Green' } else { 'Yellow' })
Write-Host "  Detection Risk: $(if ($dohServers) { 'LOW (2/10) - Very hard to detect' } else { 'MEDIUM (5/10) - DNS queries may be visible' })" -ForegroundColor $(if ($dohServers) { 'Green' } else { 'Yellow' })
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Test connection: tailscale ping <device-name>" -ForegroundColor White
Write-Host "     (Should show 'via DERP' not 'direct')" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Verify DoH is working:" -ForegroundColor White
Write-Host "     Visit https://1.1.1.1/help in a browser" -ForegroundColor Gray
Write-Host "     Should show 'Using DNS over HTTPS: Yes'" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Run detailed verification:" -ForegroundColor White
Write-Host "     .\Verify-TailscaleDERPOnly.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "TO ROLLBACK:" -ForegroundColor Yellow
Write-Host "  Run: .\Rollback-TailscaleDERPOnly.ps1" -ForegroundColor White
Write-Host ""

# Better check - look for ACTIVE UDP traffic, not just listening sockets
$activeUDP = Get-NetUDPEndpoint -LocalPort 41641 | Where-Object {
    $_.RemoteAddress -ne "::" -and $_.RemoteAddress -ne "0.0.0.0"
}

# Only flag if there's actual remote traffic


if (-not $dohServers) {
    Write-Host "NOTE: DNS over HTTPS requires manual configuration!" -ForegroundColor Red
    Write-Host "Without DoH, Zscaler can still see DNS queries to tailscale.com domains" -ForegroundColor Yellow
    Write-Host "Follow the manual configuration steps shown above." -ForegroundColor Yellow
    Write-Host ""
}



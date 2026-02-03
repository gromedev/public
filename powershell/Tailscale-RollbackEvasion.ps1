#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Rollback Tailscale DERP-only mode configuration

.DESCRIPTION
    This script removes the firewall rule blocking direct UDP connections,
    allowing Tailscale to resume normal operation with direct peer-to-peer
    connections when possible.

.NOTES
    Run as Administrator
#>

Write-Host "`n=== Tailscale DERP-Only Mode Rollback ===" -ForegroundColor Cyan
Write-Host "This will restore normal Tailscale operation (direct connections enabled)`n" -ForegroundColor Yellow

# Check if Tailscale is installed
$tailscalePath = "C:\Program Files\Tailscale\tailscale.exe"
if (-not (Test-Path $tailscalePath)) {
    Write-Warning "Tailscale not found at $tailscalePath"
    Write-Host "Script will still attempt to remove firewall rule..." -ForegroundColor Yellow
}

# Step 1: Check if firewall rule exists
Write-Host "[1/3] Checking for firewall rule..." -ForegroundColor Green
$existingRule = Get-NetFirewallRule -DisplayName "Block Tailscale Direct UDP" -ErrorAction SilentlyContinue

if (-not $existingRule) {
    Write-Warning "Firewall rule 'Block Tailscale Direct UDP' not found"
    Write-Host "    Nothing to remove - Tailscale may already be in normal mode" -ForegroundColor Yellow
} else {
    Write-Host "    Found firewall rule: Block Tailscale Direct UDP" -ForegroundColor Green
}

# Step 2: Remove firewall rule
if ($existingRule) {
    Write-Host "[2/3] Removing firewall rule..." -ForegroundColor Green
    
    try {
        Remove-NetFirewallRule -DisplayName "Block Tailscale Direct UDP" -ErrorAction Stop
        Write-Host "    SUCCESS: Firewall rule removed" -ForegroundColor Green
        Write-Host "    Direct UDP connections are now allowed" -ForegroundColor Green
    } catch {
        Write-Error "Failed to remove firewall rule: $_"
        Write-Host "    You may need to remove it manually via Windows Defender Firewall" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "[2/3] No firewall rule to remove, skipping..." -ForegroundColor Yellow
}

# Step 3: Restart Tailscale to apply changes
if (Test-Path $tailscalePath) {
    Write-Host "[3/3] Restarting Tailscale service..." -ForegroundColor Green
    
    try {
        & $tailscalePath down 2>$null
        Start-Sleep -Seconds 2
        & $tailscalePath up 2>$null
        Write-Host "    Tailscale restarted successfully" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to restart Tailscale: $_"
        Write-Host "    Please restart Tailscale manually" -ForegroundColor Yellow
    }
    
    # Verify Tailscale status
    Start-Sleep -Seconds 3
    $status = & $tailscalePath status 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n--- Current Tailscale Connections ---" -ForegroundColor Cyan
        Write-Host $status
    } else {
        Write-Warning "Could not retrieve Tailscale status"
    }
} else {
    Write-Host "[3/3] Tailscale not found, skipping restart..." -ForegroundColor Yellow
}

# Verify rollback
Write-Host "`n=== Verification ===" -ForegroundColor Cyan

# Check firewall rule is gone
$ruleCheck = Get-NetFirewallRule -DisplayName "Block Tailscale Direct UDP" -ErrorAction SilentlyContinue
if ($ruleCheck) {
    Write-Warning "Firewall rule still exists - rollback may have failed"
} else {
    Write-Host "Firewall rule: REMOVED" -ForegroundColor Green
}

# Final instructions
Write-Host "`n=== Rollback Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Normal Tailscale operation restored." -ForegroundColor Green
Write-Host ""
Write-Host "What changed:" -ForegroundColor Yellow
Write-Host "  - Direct peer-to-peer connections are now allowed" -ForegroundColor White
Write-Host "  - Tailscale will use UDP port 41641 for direct connections" -ForegroundColor White
Write-Host "  - DERP relays will only be used as fallback" -ForegroundColor White
Write-Host ""
Write-Host "To verify direct connections:" -ForegroundColor Yellow
Write-Host "  tailscale ping <device-name>" -ForegroundColor White
Write-Host "  (Look for 'direct' instead of 'via DERP')" -ForegroundColor Gray
Write-Host ""
Write-Host "To re-enable DERP-only mode:" -ForegroundColor Yellow
Write-Host "  Run: .\Setup-TailscaleDERPOnly.ps1" -ForegroundColor White
Write-Host ""

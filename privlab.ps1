<#
.SYNOPSIS
Windows Privilege Escalation Audit Script
.DESCRIPTION
Analyzes user context, privileges, and group memberships to identify potential escalation vectors
.NOTES
Author: Your Name
Safe for use in authorized environments only
#>

# Initialize Output
Write-Host "`n=== Windows Privilege Escalation Audit ===`n" -ForegroundColor Cyan

# -------------------------------
# 1. User Context Analysis
# -------------------------------
Write-Host "`n[+] User Context Information" -ForegroundColor Yellow
$currentUser = whoami
$userGroups = whoami /groups
$userPrivs = whoami /priv

Write-Host "`nCurrent User: $currentUser"

# -------------------------------
# 2. Group Membership Analysis
# -------------------------------
Write-Host "`n[+] Group Membership Analysis" -ForegroundColor Yellow
$highValueGroups = @(
    "Network Configuration Operators",
    "Backup Operators",
    "Hyper-V Administrators",
    "Print Operators",
    "DCOM Users",
    "Distributed COM Users",
    "Remote Management Users",
    "Event Log Readers",
    "Performance Log Users",
    "DNS Admins",
    "Account Operators",
    "Server Operators",
    "Cryptographic Operators"
)

$userGroups | ForEach-Object {
    foreach ($group in $highValueGroups) {
        if ($_ -match [Regex]::Escape($group)) {
            Write-Host "[!] Potentially Dangerous Group Membership: $group" -ForegroundColor Red
            switch ($group) {
                "Network Configuration Operators" {
                    Write-Host "   Exploit Potential: Registry write access to DNS/NetBT keys" -ForegroundColor DarkYellow
                    Write-Host "   Mitigation: Remove from group if not required" -ForegroundColor DarkGray
                }
                "Backup Operators" {
                    Write-Host "   Exploit Potential: File system access through backup utilities" -ForegroundColor DarkYellow
                    Write-Host "   Mitigation: Audit backup activities" -ForegroundColor DarkGray
                }
                # Add more group explanations as needed
            }
        }
    }
}

# -------------------------------
# 3. Privilege Analysis
# -------------------------------
Write-Host "`n[+] Privilege Analysis" -ForegroundColor Yellow
$dangerousPrivs = @(
    "SeImpersonatePrivilege",
    "SeAssignPrimaryTokenPrivilege",
    "SeDebugPrivilege",
    "SeLoadDriverPrivilege",
    "SeBackupPrivilege",
    "SeRestorePrivilege",
    "SeTakeOwnershipPrivilege",
    "SeTcbPrivilege"
)

$userPrivs | ForEach-Object {
    foreach ($priv in $dangerousPrivs) {
        if ($_ -match "$priv.*Enabled") {
            Write-Host "[!] Dangerous Privilege Enabled: $priv" -ForegroundColor Red
            switch ($priv) {
                "SeImpersonatePrivilege" {
                    Write-Host "   Exploit Potential: Potato-family attacks (JuicyPotato, PrintSpoofer)" -ForegroundColor DarkYellow
                    Write-Host "   Mitigation: Remove from users not requiring this privilege" -ForegroundColor DarkGray
                }
                "SeDebugPrivilege" {
                    Write-Host "   Exploit Potential: Process injection and memory dumping" -ForegroundColor DarkYellow
                    Write-Host "   Mitigation: Restrict to necessary administrative accounts" -ForegroundColor DarkGray
                }
                # Add more privilege explanations as needed
            }
        }
    }
}

# -------------------------------
# 4. Service Analysis
# -------------------------------
Write-Host "`n[+] Service Analysis" -ForegroundColor Yellow

# Check writable service binaries
Write-Host "`nChecking Writable Service Binaries..." -ForegroundColor Cyan
Get-CimInstance -ClassName Win32_Service | ForEach-Object {
    try {
        $servicePath = ($_.PathName -split '"')[1]
        $acl = Get-Acl -Path $servicePath -ErrorAction Stop
        $access = $acl.Access | Where-Object {
            $_.IdentityReference -eq $currentUser -and
            $_.FileSystemRights -match "Write|FullControl|Modify"
        }
        if ($access) {
            Write-Host "[!] Writable Service Binary Found: $($_.Name)" -ForegroundColor Red
            Write-Host "   Path: $servicePath" -ForegroundColor DarkYellow
            Write-Host "   Service Account: $($_.StartName)" -ForegroundColor DarkGray
            Write-Host "   Exploit: Replace binary and restart service" -ForegroundColor DarkYellow
        }
    }
    catch {
        # Handle inaccessible paths
    }
}

# Check unquoted service paths
Write-Host "`nChecking Unquoted Service Paths..." -ForegroundColor Cyan
Get-CimInstance -ClassName Win32_Service | Where-Object {
    $_.PathName -match '^[^"].*\.exe' -and $_.PathName -notmatch "^`""
} | ForEach-Object {
    $path = ($_.PathName -split '\.exe')[0].Trim()
    $parentDir = Split-Path $path -Parent
    try {
        $acl = Get-Acl -Path $parentDir -ErrorAction Stop
        $access = $acl.Access | Where-Object {
            $_.IdentityReference -eq $currentUser -and
            $_.FileSystemRights -match "Write|FullControl|Modify"
        }
        if ($access) {
            Write-Host "[!] Unquoted Service Path Vulnerability: $($_.Name)" -ForegroundColor Red
            Write-Host "   Path: $($_.PathName)" -ForegroundColor DarkYellow
            Write-Host "   Exploit: Place executable in writable parent directory" -ForegroundColor DarkYellow
        }
    }
    catch {
        # Handle inaccessible paths
    }
}

# -------------------------------
# 5. Registry Analysis
# -------------------------------
Write-Host "`n[+] Registry Analysis" -ForegroundColor Yellow

$registryTargets = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\DnsCache\Parameters",
    "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
)

foreach ($key in $registryTargets) {
    try {
        if (Test-Path $key) {
            $acl = Get-Acl -Path $key -ErrorAction Stop
            $access = $acl.Access | Where-Object {
                $_.IdentityReference -eq $currentUser -and
                $_.RegistryRights -match "CreateSubKey|WriteKey|FullControl"
            }
            if ($access) {
                Write-Host "[!] Writable Registry Key Found: $key" -ForegroundColor Red
                Write-Host "   Rights: $($access.RegistryRights)" -ForegroundColor DarkYellow
                Write-Host "   Exploit: Modify key values for persistence/execution" -ForegroundColor DarkYellow
            }
        }
    }
    catch {
        # Handle inaccessible keys
    }
}

# -------------------------------
# 6. Filesystem Analysis
# -------------------------------
Write-Host "`n[+] Filesystem Analysis" -ForegroundColor Yellow

# Check writable PATH directories
Write-Host "`nChecking Writable PATH Directories..." -ForegroundColor Cyan
$env:Path -split ';' | ForEach-Object {
    $dir = $_.Trim()
    try {
        if (Test-Path $dir -PathType Container) {
            $acl = Get-Acl -Path $dir -ErrorAction Stop
            $access = $acl.Access | Where-Object {
                $_.IdentityReference -eq $currentUser -and
                $_.FileSystemRights -match "Write|FullControl|Modify"
            }
            if ($access) {
                Write-Host "[!] Writable PATH Directory: $dir" -ForegroundColor Red
                Write-Host "   Exploit: DLL hijacking opportunities" -ForegroundColor DarkYellow
            }
        }
    }
    catch {
        # Handle inaccessible directories
    }
}

# -------------------------------
# 7. Additional Checks
# -------------------------------
Write-Host "`n[+] Additional Checks" -ForegroundColor Yellow

# Check AlwaysInstallElevated
try {
    $alwaysInstall = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name AlwaysInstallElevated -ErrorAction Stop
    if ($alwaysInstall -eq 1) {
        Write-Host "[!] AlwaysInstallElevated Enabled" -ForegroundColor Red
        Write-Host "   Exploit: Install malicious MSI packages as SYSTEM" -ForegroundColor DarkYellow
    }
}
catch {
    # Key doesn't exist or inaccessible
}

# Check scheduled tasks
Write-Host "`nChecking Scheduled Tasks..." -ForegroundColor Cyan
Get-ScheduledTask | ForEach-Object {
    $task = $_
    $task.Actions | ForEach-Object {
        if ($_.Execute -and (Test-Path $_.Execute -ErrorAction SilentlyContinue)) {
            try {
                $acl = Get-Acl -Path $_.Execute -ErrorAction Stop
                $access = $acl.Access | Where-Object {
                    $_.IdentityReference -eq $currentUser -and
                    $_.FileSystemRights -match "Write|FullControl|Modify"
                }
                if ($access) {
                    Write-Host "[!] Writable Scheduled Task Executable: $($task.TaskName)" -ForegroundColor Red
                    Write-Host "   Path: $($_.Execute)" -ForegroundColor DarkYellow
                }
            }
            catch {
                # Handle inaccessible paths
            }
        }
    }
}

# -------------------------------
# Final Recommendations
# -------------------------------
Write-Host "`n[+] Recommended Next Steps:" -ForegroundColor Green
Write-Host "1. Prioritize RED items for immediate investigation"
Write-Host "2. Use complementary tools for deeper analysis:"
Write-Host "   - WinPEAS: https://github.com/carlospolop/PEASS-ng"
Write-Host "   - PowerUp.ps1: https://github.com/PowerShellMafia/PowerSploit"
Write-Host "   - Seatbelt: https://github.com/GhostPack/Seatbelt"
Write-Host "3. Validate findings in controlled environment before remediation"


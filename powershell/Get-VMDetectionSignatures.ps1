function Get-VMDetectionSignatures {
    Write-Host "=== VM Detection Analysis ===" -ForegroundColor Green
    
    # Check hardware signatures
    Write-Host "`nHardware Signatures:" -ForegroundColor Yellow
    
    # BIOS information
    $bios = Get-WmiObject Win32_BIOS
    Write-Host "BIOS Version: $($bios.Version)" -ForegroundColor Cyan
    Write-Host "BIOS Manufacturer: $($bios.Manufacturer)" -ForegroundColor Cyan
    
    # System information
    $system = Get-WmiObject Win32_ComputerSystem
    Write-Host "System Manufacturer: $($system.Manufacturer)" -ForegroundColor Cyan
    Write-Host "System Model: $($system.Model)" -ForegroundColor Cyan
    
    # Check for VM-specific hardware
    $pciDevices = Get-WmiObject Win32_PnPEntity | Where-Object {
        $_.Name -match "(VMware|VirtualBox|Parallels|Hyper-V|QEMU|Virtual)"
    }
    
    if ($pciDevices) {
        Write-Host "`nVM Hardware Detected:" -ForegroundColor Red
        $pciDevices | ForEach-Object {
            Write-Host "  $($_.Name)" -ForegroundColor Red
        }
    }
    
    # Check registry keys
    Write-Host "`nRegistry Signatures:" -ForegroundColor Yellow
    
    $vmRegKeys = @(
        "HKLM:\SOFTWARE\VMware, Inc.\VMware Tools",
        "HKLM:\SOFTWARE\Oracle\VirtualBox Guest Additions",
        "HKLM:\SOFTWARE\Parallels\Parallels Tools",
        "HKLM:\SYSTEM\ControlSet001\Services\VBoxGuest",
        "HKLM:\SYSTEM\ControlSet001\Services\VMTools"
    )
    
    foreach ($key in $vmRegKeys) {
        if (Test-Path $key) {
            Write-Host "Found VM registry key: $key" -ForegroundColor Red
        }
    }
    
    # Check processes
    Write-Host "`nVM Processes:" -ForegroundColor Yellow
    $vmProcesses = Get-Process | Where-Object {
        $_.ProcessName -match "(vmware|vbox|parallels|qemu|virtual)"
    }
    
    if ($vmProcesses) {
        Write-Host "VM Processes detected:" -ForegroundColor Red
        $vmProcesses | ForEach-Object {
            Write-Host "  $($_.ProcessName)" -ForegroundColor Red
        }
    }
    
    # Check services
    Write-Host "`nVM Services:" -ForegroundColor Yellow
    $vmServices = Get-Service | Where-Object {
        $_.Name -match "(vmware|vbox|parallels|prl_|vm3d)"
    }
    
    if ($vmServices) {
        Write-Host "VM Services detected:" -ForegroundColor Red
        $vmServices | ForEach-Object {
            Write-Host "  $($_.Name) - $($_.Status)" -ForegroundColor Red
        }
    }
    
    # Check MAC address prefixes (common VM indicators)
    Write-Host "`nNetwork Adapters:" -ForegroundColor Yellow
    $adapters = Get-WmiObject Win32_NetworkAdapter | Where-Object {$_.MACAddress}
    foreach ($adapter in $adapters) {
        $mac = $adapter.MACAddress
        if ($mac) {
            $prefix = $mac.Substring(0,8)
            Write-Host "MAC: $mac" -ForegroundColor Cyan
            
            # Check for VM vendor MAC prefixes
            $vmMacPrefixes = @{
                "00:1C:42" = "Parallels"
                "00:50:56" = "VMware"
                "08:00:27" = "VirtualBox"
                "00:16:3E" = "Xen"
                "00:15:5D" = "Hyper-V"
            }
            
            foreach ($vmPrefix in $vmMacPrefixes.GetEnumerator()) {
                if ($mac.StartsWith($vmPrefix.Key)) {
                    Write-Host "VM MAC detected: $($vmPrefix.Value)" -ForegroundColor Red
                }
            }
        }
    }
}

# Run the analysis
Get-VMDetectionSignatures

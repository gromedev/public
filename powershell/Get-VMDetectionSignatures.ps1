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

function Fix-SystemIdentification {
    Write-Host "=== Simple System ID Fix ===" -ForegroundColor Green
    
    # Check admin privileges
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "❌ Run as Administrator" -ForegroundColor Red
        return
    }
    
    Write-Host "Changing system identification to appear as physical ARM PC..." -ForegroundColor Yellow
    
    # Core system identification changes
    try {
        # System information
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation" -Name "SystemManufacturer" -Value "Microsoft Corporation" -Force
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation" -Name "SystemProductName" -Value "Surface Pro 9" -Force
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation" -Name "BIOSVendor" -Value "Microsoft Corporation" -Force
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation" -Name "BIOSVersion" -Value "1.14.3684.0" -Force
        
        # BIOS information  
        Set-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" -Name "SystemManufacturer" -Value "Microsoft Corporation" -Force
        Set-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" -Name "SystemProductName" -Value "Surface Pro 9" -Force
        Set-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" -Name "BIOSVendor" -Value "Microsoft Corporation" -Force
        Set-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" -Name "BIOSVersion" -Value "UEFI: 1.14.3684.0" -Force
        
        # Computer system info
        Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" -Name "Manufacturer" -Value "Microsoft Corporation" -Force
        Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" -Name "Model" -Value "Surface Pro 9" -Force
        
        Write-Host "✅ System identification changed" -ForegroundColor Green
        Write-Host "✅ Will appear as: Microsoft Surface Pro 9" -ForegroundColor Green
        Write-Host "⚠️  Reboot required for changes to take effect" -ForegroundColor Yellow
        
    } catch {
        Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Run it
#Fix-SystemIdentification

# Run the analysis
Get-VMDetectionSignatures


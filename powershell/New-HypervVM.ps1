<# 
.AUTHOR
  thomas@grome.dev
#>
Requires the script to be run under an administrative account context.
# Requires -RunAsAdministrator
# Requires -Version 5.1

$VMLocation = "C:\Users\Public\Documents\Hyper-V\VMs"
$random = Get-Random -Minimum 100 -Maximum 999
$ISO = "C:\Users\Public\Documents\Hyper-V\en-us_windows_10_consumer_editions_version_21h2_x64_dvd_6cfdb144.iso"
$VMNetwork = "internal"
$VMSettings += [pscustomobject]@{ VMName = "Win10 - Client $random"; VMMemory = 1024MB; VMDiskSize = 126GB; VMCPUCount = 2 }

# Create the VMs
foreach($row in $VMSettings){
    $VMName = $row.VMName
    $VMMemory = $row.VMMemory
    $VMDiskSize = $row.VMDiskSize
    $VMCPUCount = $row.VMCPUCount

    Write-Output "Creating VM $VMName in $VMLocation"
    New-VM -Name $VMName -Generation 2 -BootDevice CD -MemoryStartupBytes $VMMemory -SwitchName $VMNetwork -Path $VMLocation -NoVHD | Out-Null
    New-VHD -Path "$VMLocation\$VMName\Virtual Hard Disks\$VMName-Disk1.vhdx" -SizeBytes $VMDiskSize | Out-Null
    Add-VMHardDiskDrive -VMName $VMName -Path "$VMLocation\$VMName\Virtual Hard Disks\$VMName-Disk1.vhdx" | Out-Null
    Set-VMProcessor -VMName $VMName -Count $VMCPUCount | Out-Null
    Set-VMDvdDrive -VMName $VMName -Path $ISO | Out-Null
}

Write-Output "Done!"

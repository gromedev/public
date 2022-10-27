<#
Pushes key used to BitLocker encrypt USB to Intune
#>
$RemDrive = gwmi win32_diskdrive | 
?{$_.interfacetype -eq "USB"} | 
%{gwmi -Query "ASSOCIATORS OF {Win32_DiskDrive.DeviceID=`"$($_.DeviceID.replace('\','\\'))`"} WHERE AssocClass = Win32_DiskDriveToDiskPartition"} | 
%{gwmi -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID=`"$($_.DeviceID)`"} WHERE AssocClass = Win32_LogicalDiskToPartition"} | 
%{$_.deviceid}
$BLV = Get-BitLockerVolume -MountPoint $RemDrive 
BackupToAAD-BitLockerKeyProtector -MountPoint $RemDrive -KeyProtectorId $BLV.KeyProtector[1].KeyProtectorId

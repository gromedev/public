$DiskInfo = foreach ($disk in Get-WmiObject Win32_DiskDrive) {
    [pscustomobject]@{
    "DeviceID"=$disk.DeviceID;
    "Caption"=$disk.Caption;
    "Capacity (GB)"=[math]::Round($disk.size / 1GB,0);  
    "SerialNumber" =$disk.SerialNumber
    "SCSIControllerNum"=$disk.scsiport;
    "SCSIDeviceNum"=$disk.scsitargetid;   
    }
}
$DiskInfo|ft 

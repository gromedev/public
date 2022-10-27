<# 
.SYNOPSIS
    Gets a list of managed devices that do not have a bitLocker Key and saves it to a .csv file
 .AUTHOR
    thomas@grome.dev
 #>
$outFilePath = 'c:\temp\DevicesWithNoRecoveryKeys.csv'
$hasError = $false
  
Connect-MgGraph -scopes "BitLockerKey.ReadBasic.All", "DeviceManagementManagedDevices.Read.All"
Select-MgProfile -Name v1.0
 
try{
 
    $BitLockerRecoveryKeys  = Get-MgInformationProtectionBitlockerRecoveryKey -All -Property "id, createdDateTime, deviceId" -ErrorAction Stop -ErrorVariable GraphError | Select-Object -Property id, createdDateTime, deviceId
    $ManagedDevices = Get-MgDeviceManagementManagedDevice -All -Property "deviceName,id,azureADDeviceId" -Filter "operatingSystem eq 'Windows'" -ErrorAction Stop -ErrorVariable GraphError | Select-Object -Property deviceName, id, azureADDeviceId
 
    $ManagedDevices | Where-Object { $PSItem.azureADDeviceId -notin $BitLockerRecoveryKeys.deviceId }
 
} catch {
    Write-Host "Error downloading report: $GraphError.Message"
    $hasError = $true
}
  
if(!$hasError){
    try{
        # Write-Host "Writing to .csv file..."
        $ManagedDevices  | Export-Csv -Path $outFilePath
        Write-Host "Report saved at $outFilePath"
    } catch {
        Write-Host "Error saving .csv: $_.ErrorDetails.Message"
    }
}
  
Disconnect-MgGraph

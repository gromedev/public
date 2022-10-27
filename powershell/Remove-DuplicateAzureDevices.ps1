<#
 .SYNOPSIS
    Cleans up older duplicates of Azure Device Entries with the same hardware ID (Windows only)
.AUTHOR
    thomas@grome.dev
#> 

Param(
    [Switch]$WhatIf,
    [Switch]$Force
)

#connect to MSOL
Connect-MsolService

#get all enabled AzureAD devices
$devices = Get-MsolDevice -All | Where-Object{$_.Enabled}
$hwIds = @{}
$duplicates=@{}

#create hashtable with all devices that have a Hardware ID
foreach($device in $devices){
    $physId = $Null
    foreach($deviceId in $device.DevicePhysicalIds){
        if($deviceId.StartsWith("[HWID]")){
            $physId = $deviceId.Split(":")[-1]
        }
    }
    if($physId){
        if(!$hwIds.$physId){
            $hwIds.$physId = @{}
            $hwIds.$physId.Devices = @()
            $hwIds.$physId.DeviceCount = 0
        }
        $hwIds.$physId.DeviceCount++
        $hwIds.$physId.Devices += $device
    }
}

#select HW ID's that have multiple device entries
$hwIds.Keys | ForEach-Object {
    if($hwIds.$_.DeviceCount -gt 1){
        $duplicates.$_ = $hwIds.$_.Devices
    }
}

#loop over the duplicate HW Id's
$cleanedUp = 0
$totalDevices = 0
foreach($key in $duplicates.Keys){
    $mostRecent = (Get-Date).AddYears(-100)
    foreach($device in $duplicates.$key){
        $totalDevices++
        #detect which device is the most recently active device
        if([DateTime]$device.ApproximateLastLogonTimestamp -gt $mostRecent){
            $mostRecent = [DateTime]$device.ApproximateLastLogonTimestamp
        }
    }

    foreach($device in $duplicates.$key){
        if([DateTime]$device.ApproximateLastLogonTimestamp -lt $mostRecent){
            try{
                if($Force){
                    Remove-MsolDevice -DeviceId $device.DeviceId -Force -Confirm:$False -ErrorAction Stop
                    Write-Output "Removed Stale device $($device.DisplayName) with last active date: $($device.ApproximateLastLogonTimestamp)"
                }elseif($WhatIf){
                    Write-Output "Should disable Stale device $($device.DisplayName) with last active date: $($device.ApproximateLastLogonTimestamp)"               
                }else{
                    Disable-MsolDevice -DeviceId $device.DeviceId -Force -Confirm:$False -ErrorAction Stop
                    Write-Output "Disabled Stale device $($device.DisplayName) with last active date: $($device.ApproximateLastLogonTimestamp)"
                }
                $cleanedUp++
            }catch{
                Write-Output "Failed to disable Stale device $($device.DisplayName) with last active date: $($device.ApproximateLastLogonTimestamp)"
                Write-Output $_.Exception
            }
        }
    }
}

Write-Output "Total unique hardware ID's with >1 device registration: $($duplicates.Keys.Count)"

Write-Output "Total devices registered to these $($duplicates.Keys.Count) hardware ID's: $totalDevices" 

Write-Output "Devices cleaned up: $cleanedUp"

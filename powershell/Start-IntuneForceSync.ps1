<#
.SYNOPSIS
    Starts Intune Policy Sync on all Windows devices remotely
.AUTHOR
    thomas@grme.dev

#>

##Requires -module Microsoft.Graph.Intune

Connect-MSGraph -ForceNonInteractive -ErrorAction Stop -Quiet

Write-Output "Getting Windows device list"
$deviceObjList = Get-IntuneManagedDevice | Where-Object operatingSystem -eq "Windows" | Get-MSGraphAllPages


if (($deviceObjList).count -gt 0){
    Write-Output "Pushing sync."
    foreach ($deviceObj in $deviceObjList) {
        try {
            "id: {0}    OS: {1,-8}    Name: {2,-50}    Owner: {3}" -f $deviceObj.id,$deviceObj.operatingSystem,$deviceObj.deviceName,$deviceObj.emailAddress
            $deviceObj | Invoke-IntuneManagedDeviceSyncDevice -ErrorAction Stop
        } catch {
            Write-Error "Failed to push sync to $($deviceObj.id)"
        }
    }
} else {
    Write-Output "No windows devices found."
}

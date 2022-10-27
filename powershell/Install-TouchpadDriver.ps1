<#
.SYNOPSIS
    Update touchpad driver (in this example for HP840U)
.AUTHOR
    thomas@grome.dev
#>

#Install "sp134427.exe" -s -overwrite -report %temp%
#Check for path where logs will be stored
if (!(Test-Path C:\Temp)) {
    New-Item -Path C:\ -ItemType Directory -Name Temp
    New-Item -Path C:\Temp -ItemType Directory -Name SU
}
elseif (!(Test-Path C:\Temp\SU)) {
    New-Item -Path C:\Temp -ItemType Directory -Name SU
}

function Get-Info
{
    "[$Env:ComputerName] [$Tag] [$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss').ToString())] [$($env:UserName)] [$($MyInvocation.ScriptLineNumber)]"
}

function Exit-WithCode
{
    param
    (
        $exitcode
    )

    $host.SetShouldExit($exitcode)
    exit
}

$SoftwareName = 'IntelGraphics'
#Check currently installed version of driver
$InstallationVersion = Get-CimInstance -ClassName win32_pnpsigneddriver | Select-Object devicename, manufacturer, driverversion | Where-Object {$PSItem.DeviceName -like 'Intel(R)*HD Graphics*'}
#Write driver version to file
"$(Get-Info) Installed version $($InstallationVersion.driverversion)" | Out-File -Append -FilePath c:\Temp\SU\HP840Touchpad.log
#Install drivers silently
$Process = start-process ".\HP\sp134427.exe" -ArgumentList @('-report c:\temp\su\IntelGraph.log', '-s') -NoNewWindow -Wait -PassThru
$Process.WaitForExit()
#Determine exit of installation based on exitcode of Intel  
If($Process.Exitcode -eq '0'){
    #Hard reboot
    Exit-WithCode -exitcode 1641
}else{
    #Retry
    Exit-WithCode -exitcode 1618
}

<#
.SYNOPSIS
    Install printers via Intune
.AUTHOR
    thomas@grome.dev
#>

[CmdletBinding()]

Param(
[switch]$Uninstall
)

#Declare some variables for your printer:
$PrinterName = "PrinterName"
$PrinterIP = "192.168.0.242"
$DriverName = "DeviceName"
$infFile = $PSScriptRoot + "\us015.inf"
$dppath = $PSScriptRoot + "\dpinst64.exe"

if(!$Uninstall)
{
  # Install printer driver
  Start-Process -filepath $dppath -ArgumentList "/S /SE /SW"
  $procid = (Get-Process DPinst64).id
  wait-process -id $procid

  # Add printer driver
  Add-PrinterDriver -Name $DriverName

  # Local printer port
  Add-PrinterPort -Name "TCP:$($PrinterName)" -PrinterHostAddress $PrinterIP

  # Adds printer
  Add-Printer -Name "$($PrinterName)" -PortName "TCP:$($PrinterName)" DriverName $DriverName -Shared:$false
} 
else
  {
    Start-Process -filepath $dppath -ArgumentList ("/S /SE /SW /u " + $infFile)
    Remove-printer -Name "$($PrinterName)"
    Remove-PrinterPort -Name "TCP:$($PrinterName)"
    Remove-PrinterDriver -Name $DriverName
}

<#
.AUTHOR
  thomas@grome.dev
#>

$RegPathM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
$RegPathU = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
$RegName = "NoDrives"
#$RegValue = "08" #D
$RegValue = "32" #F

If((Test-Path -LiteralPath $RegPathM) -eq $true){
    Remove-Item $RegPathM -Force -ea SilentlyContinue}

If((Test-Path -LiteralPath $RegPathU) -ne $true){
    New-Item $RegPathU -Force -ea SilentlyContinue}
New-ItemProperty -LiteralPath $RegPathU -Name $RegName -Value $RegValue -PropertyType DWORD -Force -ea SilentlyContinue

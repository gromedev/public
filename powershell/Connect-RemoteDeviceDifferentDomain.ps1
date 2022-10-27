$remoteDevice = "FullComputerName" 
$domain = "DOMAIN"
$Credential = Get-Credential
$ColItems = Get-WmiObject `
-Class Win32_Process `
-Authority "ntlmdomain:$Domain" `
-Credential $Credential `
-Locale "MS_409" `
-Namespace "root\cimv2"  `
-ComputerName $remoteDevice

foreach ($ObjItem in $colItems) 
{
write-host "Process Name:" $ObjItem.name
}

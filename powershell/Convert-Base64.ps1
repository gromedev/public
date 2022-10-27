#https://techexpert.tips/powershell/powershell-base64-encoding/

$cmd = "ls c:\temp"

$ENCODED = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
Write-Output $ENCODED

$cmd = "ZABpAHIAIABjADoAXAA="
$DECODED = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($cmd))
Write-Output $DECODED

$RegKey = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection')
$key = "*Dpa*"

$RegKey.PSObject.Properties | ForEach-Object {
  If($_.Name -like $key){
    Write-Host $_.Name ' = ' $_.Value
  }
}

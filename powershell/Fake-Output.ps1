Write-Host "PS C:\Users\tmg> $IP = `"`127.0.0.1`"`"
Write-Host "`$testPorts = @(137, 138, 139, 445)"
Write-Host ""
# Test TCP connectivity"
Write-Host ""
Write-Host "foreach (`$port in `$testPorts) {"
Write-Host "    Test-NetConnection -ComputerName $IP -Port `$port |"
Write-Host "    Select-Object -Property ComputerName, TcpTestSucceeded, RemotePort"
Write-Host "}"
Write-Host ""
Write-Host ""

Write-Host "ComputerName TcpTestSucceeded RemotePort"
Write-Host "------------ ---------------- ----------"
Write-Host "172.23.214.37            True        137"
Write-Host "172.23.214.37            True        138"
Write-Host "172.23.214.37            True        139"
Write-Host "172.23.214.37            True        445"
Write-Host ""
Write-Host ""


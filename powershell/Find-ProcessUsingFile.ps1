#The openfiles command needs to have support for local files enabled, by running openfiles /local on and restarting.

$FileOrFolderPath = "C:\Windows\System32\config\system"

if ((Test-Path -Path $FileOrFolderPath) -eq $false) {
    Write-Warning "File or directory does not exist."       
}
else {
    $LockingProcess = CMD /C "openfiles /query /fo table | find /I ""$FileOrFolderPath"""
    Write-Host $LockingProcess
}

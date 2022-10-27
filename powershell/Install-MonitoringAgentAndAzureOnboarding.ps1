<#
.SYNOPSIS
    Install Microsoft Monitoring Agent and On-board to Azure 
.AUTHOR
    thomas@grome.dev
.LINKS
    https://adamtheautomator.com/new-selfsignedcertificate/
#>

$Agent = "C:\Program Files\Microsoft Monitoring Agent\Agent"
$bit = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
$Setup = "C:\temp\MMA\Setup.exe"
$SecondWorkspaceId = ""
$SecondWorkspaceKey = ""
New-Item -Path C:\temp\MMA -ItemType "directory" -Force | Out-Null
if(("$bit" -contains "64-bit"))
{
    Write-Host "64-bit Windows Detected."
    Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?LinkId=828603" -OutFile "C:\temp\MMA\MMASetup-AMD64.exe"
    if(!(Test-Path $setup))
    {
        Start-Process -FilePath "C:\temp\MMA\MMASetup-AMD64.exe" -ArgumentList "/c /t:C:\temp\MMA"
        Start-Sleep -Second 5
    }
}
    elseif(("$bit" -contains "32-bit"))
    {
        Write-Host "32-bit Windows Detected."
        Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?LinkId=828604" -OutFile "C:\temp\MMA\MMASetup-i386.exe"
        if(!(Test-Path $Setup))
        {
            Start-Process -FilePath "C:\temp\MMA\MMASetup-i386.exe" -ArgumentList "/c /t:C:\temp\MMA"
            Start-Sleep -Second 5
        }
    }
Start-Process -FilePath $Setup -ArgumentList '/qn NOAPM=1 ADD_OPINSIGHTS_WORKSPACE=1 OPINSIGHTS_WORKSPACE_AZURE_CLOUD_TYPE=0 OPINSIGHTS_WORKSPACE_ID="0000-0000-0000" OPINSIGHTS_WORKSPACE_KEY="0000-0000-0000" AcceptEndUserLicenseAgreement=1'
Start-Sleep -Second 5
if((Test-Path $Agent))
{
    Write-Host "Agent installation successful."
    Write-Host "Checking connection status..."
    Start-Sleep -Second 5
    Get-Service -name healthservice | Write-Output
    Write-Host ""
    Write-Host "Adding additional workspace..."
    Start-Sleep -Second 5
    $AgentCfg = New-Object -ComObject AgentConfigManager.MgmtSvcCfg
    $AgentCfg.AddCloudWorkspace($SecondWorkspaceID,$SecondWorkspaceKey)
    Write-Host "Removing installation files..."   
    Start-Sleep -Second 20
    Get-ChildItem C:\temp\ | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "Finished."
    exit
}
else {
    Write-Host "Agent installation failed."
    exit
}

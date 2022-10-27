<#
.AUTHOR
thomas@grome.dev
    
.DESCRIPTION
Reset breakglass password with randomly generated string for two accounts (btg1, btg2) on target tenant. 

1) Checks if required modules are installed. If not, prompts user to install them. 
2) Checks if password has been been reset within past six months.
3) If not, generates random password and sets it. 
#>

If(-not (Get-Module Azuread, MSOnline -ListAvailable -Verbose)){
$installModule = Read-Host "You are missing required modules. Install? y/n"
if ($installModule -eq 'y') {
    Install-Module Azuread -Scope CurrentUser -Force -Verbose
    Install-Module MSOnline -Scope CurrentUser -Force -Verbose
    }
}

$Credential = Get-Credential
$TenantId = ""
$domain = "luksys.dk"
$userObjectIdBTGAccount1 = "btg1@"+$domain
$userObjectIdBTGAccount2 = "btg2@"+$domain

Connect-AzureAD -TenantId $TenantId -Credential $Credential
Connect-MsolService -Credential $Credential

#BTG Account 1
If ($Btg1check = Get-MsolUser -UserPrincipalName $userObjectIdBTGAccount1 | Where-Object {$_.LastPasswordChangeTimeStamp -gt (Get-Date).adddays(-180)}) {
    Write-Host "$userObjectIdBTGAccount1 : It has been < 180 days since last password reset. Do nothing." -ForegroundColor Green
    Get-MsolUser -UserPrincipalName $userObjectIdBTGAccount1 | Select-Object LastPasswordChangeTimeStamp | FT -Autosize
    Get-MsolUserRole -UserPrincipalName $userObjectIdBTGAccount1 | Select-Object Name | FT -Autosize
} else {
    Write-Host "It has been >= 180 days since last password reset. Resetting password for $userObjectIdBTGAccount1" -ForegroundColor Red
    Add-Type -AssemblyName System.Web
    $genPass1 = [System.Web.Security.Membership]::GeneratePassword(40,1)
    $newPass1 = Convertto-SecureString $genPass1 -AsPlainText -Force
    Set-AzureADUserPassword -ObjectId $userObjectIdBTGAccount1 -Password $newPass1 
    Write-Host $genPass1 
}

#BTG Account 2
If ($Btg2check = Get-MsolUser -UserPrincipalName $userObjectIdBTGAccount2 | Where-Object {$_.LastPasswordChangeTimeStamp -gt (Get-Date).adddays(-180)}) {
    Write-Host  "$userObjectIdBTGAccount2 : It has been < 180 days since last password reset. Do nothing." -ForegroundColor Green
    Get-MsolUser -UserPrincipalName $userObjectIdBTGAccount2 | Select-Object LastPasswordChangeTimeStamp | FT -Autosize
    Get-MsolUserRole -UserPrincipalName $userObjectIdBTGAccount2 | Select-Object Name | FT -Autosize
} else {
    Write-Host "It has been >= 180 days since last password reset. Resetting password for $userObjectIdBTGAccount2" -ForegroundColor Red
    Add-Type -AssemblyName System.Web
    $genPass2 = [System.Web.Security.Membership]::GeneratePassword(40,1)
    $newPass2 = Convertto-SecureString $genPass2 -AsPlainText -Force
    Set-AzureADUserPassword -ObjectId $userObjectIdBTGAccount2 -Password $newPass2 
    Write-Host $genPass2
}

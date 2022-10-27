<#
.INFO
    thomas@grome.dev
#>
$scopes = @(
    "User.Read.All"
    "Group.Read.All"
    "Device.Read.All"
     "DeviceManagementManagedDevices.Read.All"
)
Select-MgProfile "Beta"

$context = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext
$token = ([Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, $null, "https://graph.microsoft.com")).AccessToken
            
$propertiesSelector = @("extensionAttributes","id","accountEnabled","createdDateTime","approximateLastSignInDateTime","deviceId","displayName","onPremisesSyncEnabled","operatingSystem","profileType","trustType","sourceType")

if(!$nonInteractive){
    Write-Progress -Activity "Azure AD Device Report" -Status "Grabbing all devices in your AD" -Id 1 -PercentComplete 0
}

$users = @()
$userData = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/users?`$select=*" -Method GET -Headers @{"Authorization"="Bearer $token"}
$users += $userData.value
while($userData.'@odata.nextLink'){
    if(!$nonInteractive){
        Write-Progress -Activity "Azure AD user Report" -Status "Grabbing all users in your AD ($($users.count))" -Id 1 -PercentComplete 0
    }
    $userData = Invoke-RestMethod -Uri $userData.'@odata.nextLink' -Method GET -Headers @{"Authorization"="Bearer $token"}    
    $users += $userData.value
}
$users

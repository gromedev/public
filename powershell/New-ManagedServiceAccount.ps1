Add-KdsRootKey –EffectiveTime ((get-date).addhours(-10))   
$gMSA_ServiceAccount = ''
$gMSA_HostNames = ''
$gMSA_DNSHostNames = ''
$gMSA_HostsGroupName = ''
New-ADGroup -Name $gMSA_HostsGroupName -GroupScope Global -PassThru
New-ADServiceAccount $gMSA_ServiceAccount `
 -DNSHostName $gMSA_DNSHostNames `
 -PrincipalsAllowedToRetrieveManagedPassword $gMSA_HostsGroupName `
 -KerberosEncryptionType RC4, AES128, AES256 `
 -ServicePrincipalNames
#Set-ADServiceAccount $gMSA_ServiceAccount -PrincipalsAllowedToRetrieveManagedPassword $gMSA_HostsGroupName

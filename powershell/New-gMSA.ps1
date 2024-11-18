New-ADServiceAccount -Name gMSA-Docker -DNSHostName srv-docker-01.i.cphtec.com -PrincipalsAllowedToRetrieveManagedPassword gMSA-Docker-Servers `
-KerberosEncryptionType AES128, AES256

Install-ADServiceAccount -Identity gMSA-Docker

Test-ADServiceAccount gMSA-Docker

New-CredentialSpec -AccountName gMSA-Docker

# sc config YourServiceName obj= "DOMAIN\gMSA-Docker$" password= ""

# Typically found C:\ProgramData\docker\credentialspecs

# docker run --security-opt "credentialspec=file://gMSA-Docker.json" -d your-container-image

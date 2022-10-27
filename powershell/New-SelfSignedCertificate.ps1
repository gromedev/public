<#
.SYNOPSIS
    Create a self-signed certificate in the local machine personal certificate store and store the result in the $cert variable. 
.AUTHOR
    thomas@grome.dev
.LINKS
    https://adamtheautomator.com/new-selfsignedcertificate/
#>

$cert = New-SelfSignedCertificate -Subject xxx

# Display the new certificate properties
$cert | Format-List -Property *

# Create a self-signed SAN certificate in the local machine personal certificate store and store the result in the $cert variable.
$cert = New-SelfSignedCertificate -DnsName example.local,ad.example.local,lab.example.local

# Display the new certificate properties
$cert | Format-List -Property *

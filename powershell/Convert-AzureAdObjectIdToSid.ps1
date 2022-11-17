function Convert-AzureAdObjectIdToSid {
<#
.SYNOPSIS
Convert an Azure AD Object ID to SID
 
.DESCRIPTION
Converts an Azure AD Object ID to a SID.
To add your own Group as a member of local Administrators, you need to provide its Security Identifier (SID), a unique value of variable length used to identify the Group.
I recommend a PowerShell script: Convert-AzureAdObjectIdToSid .ps1 (written by Oliver Kieselbach) that allows you to easily convert Azure Group Object ID into SID

Source: https://hmaslowski.com/f/configure-local-admins-via-custom-oma-uri-policy-in-memintune

.OMA-URI

./Device/Vendor/MSFT/Policy/Config/RestrictedGroups/ConfigureGroupMembership


.EXAMPLE XML

<groupmembership>
	<accessgroup desc = "Administrators">
		<member name = "Administrator" />
		<member name = "S-1-5-21-2340351570-1149635225-1902083613-42371" />
		<member name = "S-1-12-1-969599676-1192297624-3826145923-3009011932" />
	</accessgroup>
</groupmembership>




--> S-1-5-21-2340351570-1149635225-1902083613-42371 Group Name
--> S-1-12-1-969599676-1192297624-3826145923-3009011932 Azure/user


 
.PARAMETER ObjectID
The Object ID to convert
#>

    param([String] $ObjectId)

    $bytes = [Guid]::Parse($ObjectId).ToByteArray()
    $array = New-Object 'UInt32[]' 4

    [Buffer]::BlockCopy($bytes, 0, $array, 0, 16)
    $sid = "S-1-12-1-$array".Replace(' ', '-')

    return $sid
}

$objectId = "8defd89d-7ce3-4050-9aa9-1f8eb60c4c2c"
$sid = Convert-AzureAdObjectIdToSid -ObjectId $objectId
Write-Output $sid

# Converted Output from exttmg@scangl.com ObjectID:

# S-1-12-1-2092902825-1333966493-4097151155-3022111827
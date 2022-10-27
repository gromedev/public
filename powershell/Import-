<#
.AUTHOR
thomas@grome.dev
    
.DESCRIPTION
Imports GPO backup from a source domain controller into another domain.  

1) Creates an array based on directory names in $PATH.
2) Assigns variables in a loop based on directory names.
3) Creates GPO in target.
4) Imports GPO from backup.
5) Links GPO to target OU.
#>

$PATH = "C:\temp\group-policies"
#$TARGET = Get-ChildItem -path . -Recurse -Filter link.txt | Get-Content
$TARGET = "ou=test,dc=ad,dc=luksys,dc=dk"
#$GpoExists = Get-GPO -name $NewGPOParameters
#$LinkExists = Get-GPInheritance -Target $TARGET

#Create variables based on values in $ARRAY
Write-Host "Creating Array"
[String[]]$ARRAY = Get-ChildItem -path $PATH -Directory | 
         Where-Object {$_.PSIsContainer} | 
         Foreach-Object {$_.Name}

# Processes the array
Foreach ($NewGPOParameters in $ARRAY)
    {
    Write-Host "Assigning Variable"
        try {
            Write-Host "`nCreating GPOs" -ForegroundColor Green
            New-GPO $NewGPOParameters

            #Imports GPO into newly created GPO from above
            Write-Host "`nImporting backup GPO content" -ForegroundColor Green
            Import-GPO -BackupGpoName $NewGPOParameters -TargetName $NewGPOParameters -path $PATH\$NewGPOParameters

            #Links imported GPOs to OU
            Write-Host "`nLinking GPOs to target OU" -ForegroundColor Green
            New-GPLink -Name $NewGPOParameters -Target $TARGET
        }
        catch {
            Write-Output $_.Exception.Message
        }
    }

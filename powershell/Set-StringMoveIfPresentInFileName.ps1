$PATH = "D:\Windows\SYSVOL\sysvol\dom01.local\Policies\PolicyDefinitions\en-US"
$DEST = "D:\Windows\SYSVOL\sysvol\dom01.local\Policies"
$FileList = Get-ChildItem -Path $PATH -Filter "*.adml"

foreach ($File in $FileList) {
    $File.Name -match '-';
    if ($Matches) {
        $NEWDEST = $DEST -f $Matches.filename;
            Move-Item -Path $File.Name -Destination $NEWDEST;
    }
    $matches = $null
}


Set-StringReplaceInFileName.ps1

<#
Run this script using the logged on credentials
Yes
Enforce script signature check
No
Run script in 64 bit PowerShell Host
No<#﻿

#>
$ShortcutName = "Microsoft Teams"
$ShortcutName = "Microsoft Edge"
$Desktop = [Environment]::GetFolderPath("Desktop")

If (Test-Path "$Desktop\$ShortcutName.lnk") {
    #Remove Desktop Shortcut
    Remove-item -path $Desktop\* -filter "$ShortcutName.lnk"

    If (Test-Path "$Desktop\$ShortcutName.lnk") {
        Write-Host "$ShortcutName Not Removed"
        Exit 1

    } Else {
        Write-Host "$ShortcutName Removed Successfully"
        Exit 0
}

} Else {
    Write-Host "$ShortcutName Shortcut Not Detected"
    Exit 0
}


If (Test-Path "$Desktop\$ShortcutName2.lnk") {
    #Remove Desktop Shortcut
    Remove-item -path $Desktop\* -filter "$ShortcutName.lnk"

    If (Test-Path "$Desktop\$ShortcutName.lnk") {
        Write-Host "$ShortcutName Not Removed"
        Exit 1

    } Else {
        Write-Host "$ShortcutName Removed Successfully"
        Exit 0
}

} Else {
    Write-Host "$ShortcutName Shortcut Not Detected"
    Exit 0
}

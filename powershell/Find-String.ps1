Get-ChildItem -Path 'YourDirectoryPath' -Recurse | Select-String -Pattern 'merge' -CaseSensitive:$false

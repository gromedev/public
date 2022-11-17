<#
.SYNOPSIS
    Triggers ASR rule: Block JavaScript or VBScript from launching downloaded executable content.

.AUTHOR
    thomas@grome.dev
#>

# Start of function
function Test-impedeJsOrVBAExecutablesRule() {
# JSON request body that makes a XML request and utilizes WScript to execute calc.exe as an object
$body = @"
// SCPT:xmlHttpRequest
var xmlHttp = WScript.CreateObject("MSXML2.XMLHTTP");
xmlHttp.open("GET", "https://www.bing.com", false);
xmlHttp.send();

// SCPT:JSRunsFile
var shell = WScript.CreateObject("WScript.Shell");
shell.Run("calc.exe");
"@

# translates body to a local js file
set-content -Path .\dltest.js $body
# exectutes the process
start-process .\dltest.js 
# wait 5 seconds to allow executable launch before removing js 
Start-Sleep 5
remove-item .\dltest.js  
}
Test-impedeJsOrVBAExecutablesRule
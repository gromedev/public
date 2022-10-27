##Require SharePointPnPPowerShellOnline
#Set Parameters
$SiteURL = "https://DEMO.sharepoint.com/"
$outputFilePath = "c:\temp"
$keyword="Microsoft"

$currentTime=$(get-date).ToString("yyyyMMddHHmmss");
$outputFilePath="C:\PnPScript\results-"+$currentTime+".csv"
#$credentials=Get-Credential

## Connect to SharePoint Online site
 Connect-PnPOnline -Url $SiteURL -UseWebLogin
 Write-Host "Site connected sucessfully" -ForegroundColor Green
## Executes an arbitrary search query against the SharePoint search index

$results=Submit-PnPSearchQuery -Query $keyword #-MaxResults 10 #here it will export 10 items in search result

## Get the results in the hash table
$hashTable=@()
foreach($resultRow in $results.ResultRows)
{
    $obj=New-Object PSObject
    $resultRow.GetEnumerator()| ForEach-Object{ $obj | Add-Member Noteproperty $_.Key $_.Value}
    $hashTable+=$obj;
    $obj=$null;
}

## Export to CSV
$hashtable | export-csv $outputFilePath -NoTypeInformation
 Write-Host "Result exported sucessfully" -ForegroundColor Yellow

<#
.SYNOPSIS
    The following REST API call is to get the InTune report data for the tenant.
.AUTHOR
    thomas@grome.dev
.LINK
    https://pankajsurti.com/2022/07/07/how-to-export-export-intune-reports-using-graph-apis/
.EXAMPLE
    Run the script - no individual functions exposed. No need to .source.
#>


function Get-IntuneReports {
    # Init Variables
    $outputPath    = "C:\temp"
    $outputCSVPath = "C:\temp\EAWFAreport.zip"  #might need changed

    $ApplicationID   = "71588523-56bf-4156-b9ba-80dc5de38f10"
    $TenantID        = "c5f756ff-5bb3-4640-8330-29b52ffbd0b8"
    $AccessSecret    = "Ik18Q~5TiguKW.k7eiAt.uNK8eJFnmbzkE4r9a_6"
    #AccessSecretValue = ""
    #"69dee7ca-c20e-4ec8-9e1e-3321bfa40d55

    #Create an hash table with the required value to connect to Microsoft graph
    $Body = @{    
        grant_type    = "client_credentials"
        scope         = "https://graph.microsoft.com/.default"
        client_id     = $ApplicationID
        client_secret = $AccessSecret
    } 

    #Connect to Microsoft Graph REST web service
    $ConnectGraph = Invoke-RestMethod -Uri https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token -Method POST -Body $Body

    #Endpoint Analytics Graph API
    $GraphGroupUrl = "https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs"

    # define request body as PS Object
    $requestBody = @{
        reportName = "Devices"
        select = @(
            "DeviceId"
            "DeviceName"
            "SerialNumber"
            "ManagedBy"
            "Manufacturer"
            "Model"
            "GraphDeviceIsManaged"
        )

    }

    # Convert to PS Object to JSON object
    $requestJSONBody = ConvertTo-Json $requestBody

    #define header, use the token from the above rest call to AAD.
    # in post method define the body is of type JSON using content-type property.
    $headers = @{
        'Authorization' = $(“{0} {1}” -f $ConnectGraph.token_type,$ConnectGraph.access_token)
        'Accept' = 'application/json;'
        'Content-Type' = "application/json"
    }

    #This API call will start a process in the background to #download the file.
    $webResponse = Invoke-RestMethod $GraphGroupUrl -Method 'POST' -Headers $headers -Body $requestJSONBody -verbose


    #If the call is a success, proceed to get the CSV file.
    if ( -not ( $null -eq $webResponse ) )
    {
        #Check status of export (GET) until status = complete
        do
        {

    #format the URL to make a next call to get the file location.
            $url2GetCSV = $("https://graph.microsoft.com/beta/deviceManagement/reports/exportJobs('{0}')" -f $webResponse.id)
            "Calling $url2GetCSV"
            $responseforCSV = Invoke-RestMethod $url2GetCSV -Method 'GET' -Headers $headers  -verbose
            if (( -not ( $null -eq $responseforCSV ) ) -and ( $responseforCSV.status -eq "completed"))
            {
                #download CSV from "URL=" to OutputCSVPath
                #### It means the completed status is true, now get the file.
                Invoke-WebRequest -Uri $responseforCSV.url -OutFile $outputCSVPath
		    # Un Zip the file.
                Expand-Archive -LiteralPath $outputCSVPath -DestinationPath $outputPath

            }
            {
                Write-Host "Still in progress..."
            }
            Start-Sleep -Seconds 10 # Delay for 10 seconds.
        } While (( -not ( $null -eq $responseforCSV ) ) -and ( $responseforCSV.status -eq "inprogress"))

    }
}

Get-IntuneReports -verbose
$responseforCSV

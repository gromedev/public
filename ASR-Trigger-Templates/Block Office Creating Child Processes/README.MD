.SYNOPSIS

	Trigger rule invokes VBA to call Win32 API. Macros allow any Win32 DLL to be imported and run. 
	
.AUTHOR
	thomas@grome.dev
	

.ASR RULE

	This rule blocks Office apps from creating child processes. Office apps include Word, Excel, PowerPoint, OneNote, and Access.

	Creating malicious child processes is a common malware strategy. Malware that abuses Office as a vector often runs VBA macros and exploit code to download and attempt to run more payloads. However, some legitimate line-of-business applications might also generate child processes for benign purposes; such as spawning a command prompt or using PowerShell to configure registry settings.

	Intune name: Office apps launching child processes

	Configuration Manager name: Block Office application from creating child processes

	GUID: d4f940ab-401b-4efc-aadc-ad5f3c50688a

	Advanced hunting action type:

	AsrOfficeChildProcessAudited
	AsrOfficeChildProcessBlocked
	Dependencies: Microsoft Defender Antivirus


	
.SOURCE CODE
	Sub Workbook_Open()
	'
	' Workbook_Open Macro
	' Executes calc.exe via a shell command
	'
		Shell "calc.exe", vbNormalFocus
	'
	End Sub

	' Workbook_Close Macro
	' On close will remove this document from Trusted

	Private Sub Workbook_Close()
		On Error GoTo ErrorHandler
		Set WshShell = CreateObject("WScript.Shell")
		WshShell.RegDelete "HKEY_CURRENT_USER\Software\Microsoft\Office\16.0\Word\Security\Trusted Documents\TrustRecords\"
	ErrorHandler:
	End Sub

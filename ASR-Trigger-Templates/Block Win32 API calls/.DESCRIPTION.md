.SYNOPSIS
	Trigger rule invokes VBA to call Win32 API. Macros allow any Win32 DLL to be imported and run. 
	
.AUTHOR
	thomas@grome.dev

.ASR RULE
	Block Win32 API calls from Office macros
	This rule prevents VBA macros from calling Win32 APIs.

	Office VBA enables Win32 API calls. Malware can abuse this capability, such as calling Win32 APIs to launch malicious shellcode without writing anything directly to disk. Most organizations don't rely on the ability to call Win32 APIs in their day-to-day functioning, even if they use macros in other ways.

	Supported operating systems:

	Windows 10, version 1709
	Windows Server, version 1809
	Windows Server 2019
	Configuration Manager CB 1710
	Intune name: Win32 imports from Office macro code

	Configuration Manager name: Block Win32 API calls from Office macros

	GUID: 92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b

	Advanced hunting action type:

	AsrOfficeMacroWin32ApiCallsAudited
	AsrOfficeMacroWin32ApiCallsBlocked
	Dependencies: Microsoft Defender Antivirus, AMSI
	
	
	
.SOURCE CODE

	Private Declare PtrSafe Sub Sleep Lib "kernel32" (ByVal dwMilliseconds As Long)
	' This code triggers  rule invokes VBA to call Win32 API. "Block Win32 API calls from Office macros"
	'Wait two seconds and execute before running executable
	 
	Sub Workbook_Open()
		Sleep 2000
		WscriptExec "calc.exe"
	End Sub

	' Exec process using WScript.Shell
	Sub WscriptExec(targetPath As String)
		CreateObject("WScript.Shell").Run targetPath, 1
	End Sub


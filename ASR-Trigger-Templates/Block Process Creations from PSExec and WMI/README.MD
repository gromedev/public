.SYNOPSIS

	Triggers ASR rule regarding process creations from psexe and/or WMI - in this example calc.exe
	
	
.AUTHOR
	thomas@grome.dev


.ASR RULE

	Block process creations originating from PSExec and WMI commands
	This rule blocks processes created through PsExec and WMI from running. Both PsExec and WMI can remotely execute code. There's a risk of malware abusing functionality of PsExec and WMI for command and control purposes, or to spread an infection throughout an organization's network.

	 Warning

	Only use this rule if you're managing your devices with Intune or another MDM solution. This rule is incompatible with management through Microsoft Endpoint Configuration Manager because this rule blocks WMI commands the Configuration Manager client uses to function correctly.

	Intune name: Process creation from PSExec and WMI commands

	Configuration Manager name: Not applicable

	GUID: d1e49aac-8f56-4280-b9ba-993a6d77406c

	Advanced hunting action type:

	AsrPsexecWmiChildProcessAudited
	AsrPsexecWmiChildProcessBlocked
	Dependencies: Microsoft Defender Antivirus
	
	
	
.SOURCE CODE

on error resume next
' Creates object to be used from Win32 provider
set process = GetObject("winmgmts:Win32_Process")
' Creates the executable process - calc.exe 
result = process.Create ("calc.exe",null,null,processid)

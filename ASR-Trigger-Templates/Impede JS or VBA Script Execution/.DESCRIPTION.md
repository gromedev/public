.SYNOPSIS


.ASR RULE
	Block JavaScript or VBScript from launching downloaded executable content
  This rule prevents scripts from launching potentially malicious downloaded content. Malware written in JavaScript or VBScript often acts as a downloader to fetch and launch other malware from the Internet.

Although not common, line-of-business applications sometimes use scripts to download and launch installers.

Intune name: js/vbs executing payload downloaded from Internet (no exceptions)

Configuration Manager name: Block JavaScript or VBScript from launching downloaded executable content

GUID: d3e037e1-3eb8-44c8-a917-57927947596d

Advanced hunting action type:

AsrScriptExecutableDownloadAudited
AsrScriptExecutableDownloadBlocked
Dependencies: Microsoft Defender Antivirus, AMSI

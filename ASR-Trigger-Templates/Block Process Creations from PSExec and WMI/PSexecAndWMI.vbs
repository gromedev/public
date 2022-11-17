on error resume next
' Creates object to be used from Win32 provider
set process = GetObject("winmgmts:Win32_Process")
' Creates the executable process - calc.exe 
result = process.Create ("calc.exe",null,null,processid)
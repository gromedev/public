<#
.AUTHOR
  thomas@grome.dev
#>

Function Invoke-CatFact 
{
    Add-Type -AssemblyName System.Speech
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $catFacts = "https://pastebin.com/raw/FwNwnj7H"
    $random = Get-Random -minimum 20 -maximum 60
    Start-Sleep -s $random
    $voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $web = (Invoke-WebRequest -uri $catFacts).tostring() -split "[`n]"
    $random = Get-Random $web
    #$speak.Volume = 10
    $voice.Speak("Did you know?")
    $voice.Speak($random)
}

Invoke-CatFact 

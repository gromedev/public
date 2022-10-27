<#
.SYNOPSIS
    Download videos from websites

.AUTHOR
    thomas@grome.dev

.REQUIREMENTS
    yt-dlp
    change path to install dir

#>
function Save-Video {
    Param ($URLIn,$p,$NameIn)
    $args = "-i --download-archive phchannel.txt -f best"
    $program = "C:\yt-dlp.exe" #path to youtube-dlp exe file

      If(!(Test-Path $p\$URLIn)){

        New-Item -ItemType Directory -Force -Path $p\$NameIn
}

    Start-Process $program -ArgumentList $URLIn, $args -WorkingDirectory $p\$NameIn
    Write-Host "Downloading " $NameIn "Channel"
    Start-Sleep -Seconds 720 ## wait a few minutes to avoid throttling

}

##PH
$savepathph = "c:\temp"
Save-Video 'https://www.SITEYOUWANTTORIP.com'  $savepathph 'ripped-video'

Get-ChildItem c:\temp -Recurse | Where-Object {$_.Extension -eq ".m3u8"} | Rename-Item -NewName {"$($_.BaseName).mp4"}

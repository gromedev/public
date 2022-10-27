<# Looking at windows event logs can be time consuming and tedious, so here is a short PowerShell script to parse the event log on a target machine for recent commands 

# Or 1 liner
$commands = @() ; (Invoke-Command -ScriptBlock {Get-WinEvent -MaxEvents 1000 -FilterHashTable @{ LogName = "Security"; ID = 4688 }} -ComputerName $computerName ) | % { $commands += $_ ; $time = $_.TimeCreated ; $_.Message -split "\n" } | ? { $_ -match "Process Command Line" } | % { $command = ([String]$_ -split ":",2)[1].Trim() ; Write-Host "[$($time)] $($command)" }

#>

Param(
    [Parameter(Mandatory=$true)]
    [String]
    $computerName,
    
    [Int]
    $maxEvents = 1000
)

$commands = @()

(Invoke-Command -ArgumentList $maxEvents -ScriptBlock {
    Get-WinEvent -MaxEvents $Args[0] -FilterHashTable @{ LogName = "Security"; ID = 4688 }
} -ComputerName $computerName ) | 
Foreach-Object { 
    $commands += $_
    $time = $_.TimeCreated ; $_.Message -split "\n" } | 
    Where-Object { $_ -match "Process Command Line" } | 
    Foreach-Object { $command = ([String]$_ -split ":",2)[1].Trim()
    Write-Host "[$($time)] $($command)" 
}

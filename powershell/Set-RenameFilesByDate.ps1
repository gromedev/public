<#
#The % symbol is the shorthand for the "ForEach-Object" cmdlet.

1..12|%{ New-Item -ItemType Directory -Name ("2022-{0}" -f ([string]$_).PadLeft(2,"0")) -Path C:\temp\ }
#>


# creates folders named YYYY-MM. 

$month = 1..12
foreach ($SingleMonth in $Month)
    {
    $Name = "2022-{0:d2}" -f $SingleMonth 
    new-Item -ItemType Directory -Name $Name -Path $env:temp
    }

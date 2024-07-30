Add-Type -assemblyName System.Windows.Forms;

$a=@(-3..3);

while(1){
    $X = [System.Windows.Forms.Cursor]::Position.X + ($a|get-random)
    $Y = [System.Windows.Forms.Cursor]::Position.Y + ($a|get-random)
    [System.Windows.Forms.Cursor]::Position=New-Object System.Drawing.Point($x,$y);
    start-sleep -seconds 59
}

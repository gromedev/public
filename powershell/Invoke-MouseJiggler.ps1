<#
.DESCRIPTION 
  Simulates physical mouse movements by using the SendInput function from the Windows API to create slight mouse movements every second.
  This programmatically generated activity is designed to prevent the desktop from entering sleep mode by mimicking user interaction.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -MemberDefinition @"
    [DllImport("user32.dll", EntryPoint = "SendInput", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, ref INPUT pInputs, int cbSize);

    public struct INPUT {
        public int type;
        public MOUSEINPUT mi;
    }

    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    public const int INPUT_MOUSE = 0;
    public const uint MOUSEEVENTF_MOVE = 0x0001;
"@ -Name "User32" -Namespace "WinAPI"

$inp = New-Object WinAPI.User32+INPUT
$inp.type = [WinAPI.User32]::INPUT_MOUSE
$inp.mi.dx = 1
$inp.mi.dy = 1
$inp.mi.dwFlags = [WinAPI.User32]::MOUSEEVENTF_MOVE

while ($true) {
    [WinAPI.User32]::SendInput(1, [ref]$inp, [System.Runtime.InteropServices.Marshal]::SizeOf($inp))
    Start-Sleep -Seconds 1
}

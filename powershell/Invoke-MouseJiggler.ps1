function Invoke-MouseJiggler {
    [CmdletBinding()]  # Enables the use of common parameters like -Verbose
    param ()

    # Add the System.Windows.Forms assembly to enable advanced functionality
    Write-Verbose "Adding System.Windows.Forms assembly..."
    Add-Type -AssemblyName System.Windows.Forms

    # Add a new type definition for interacting with Windows API functions
    Write-Verbose "Defining Windows API functions and structures..."
    Add-Type -MemberDefinition @"
        [DllImport("user32.dll", EntryPoint = "SendInput", SetLastError = true)]
        public static extern uint SendInput(uint nInputs, ref INPUT pInputs, int cbSize);

        // Define the structure for INPUT, which will hold mouse input information
        public struct INPUT {
            public int type;             // Type of input (mouse, keyboard, etc.)
            public MOUSEINPUT mi;        // Mouse input data
        }

        // Define the structure for MOUSEINPUT, which specifies mouse action details
        public struct MOUSEINPUT {
            public int dx;               // Horizontal movement
            public int dy;               // Vertical movement
            public uint mouseData;       // Additional data (e.g., mouse wheel)
            public uint dwFlags;         // Flags indicating the mouse action
            public uint time;            // Timestamp for the event
            public IntPtr dwExtraInfo;   // Extra information for the event
        }

        // Constants for input type and flags
        public const int INPUT_MOUSE = 0;         // Input type for mouse
        public const uint MOUSEEVENTF_MOVE = 0x0001;  // Flag for mouse movement
"@ -Name "User32" -Namespace "WinAPI"

    # Create an instance of the INPUT structure for simulating mouse movement
    Write-Verbose "Creating an instance of the INPUT structure..."
    $inp = New-Object WinAPI.User32+INPUT
    $inp.type = [WinAPI.User32]::INPUT_MOUSE      # Set the input type to mouse
    $inp.mi.dx = 1                                # Set horizontal movement to 1 unit
    $inp.mi.dy = 1                                # Set vertical movement to 1 unit
    $inp.mi.dwFlags = [WinAPI.User32]::MOUSEEVENTF_MOVE  # Specify the action as a mouse move

    Write-Verbose "Entering infinite loop to simulate mouse movement..."
    # Infinite loop to keep the script running and sending input
    while ($true) {
        # Send the simulated mouse input to the system
        Write-Verbose "Sending simulated mouse movement..."
        [WinAPI.User32]::SendInput(1, [ref]$inp, [System.Runtime.InteropServices.Marshal]::SizeOf($inp)) > $null
        
        # Pause for 1 second between movements
        Write-Verbose "Sleeping for 1 second..."
        Start-Sleep -Seconds 1
    }
}

# Call the function with the -Verbose switch
Invoke-MouseJiggler -Verbose

You're absolutely right. For the PoC to work correctly, the second script should continue running and capture all traffic until you decide to stop it manually. I’ll remove all functions that stop the `tcpdump` process and disable monitor mode, allowing it to run continuously. Here are the updated scripts:

### 🔹 **1. Bash Script for Capturing the WPA2 Handshake (`capture_handshake.sh`)**

This script captures the WPA2 handshake from your Kali machine.

```bash
#!/bin/bash

# Define the wireless interface and put it into monitor mode
INTERFACE="wlan0"  # Adjust if necessary
airmon-ng start $INTERFACE

# Set the monitor mode interface name
MONITOR_INTERFACE="${INTERFACE}mon"

# Specify target network details (replace with actual details found via airodump-ng)
TARGET_BSSID="AA:BB:CC:DD:EE:FF"  # Replace with your network's BSSID
CHANNEL="6"  # Replace with your network's channel

# Start capturing traffic to capture the WPA2 handshake
airodump-ng --bssid $TARGET_BSSID -c $CHANNEL -w capture $MONITOR_INTERFACE &

# Sleep for an extended period to ensure capturing of the handshake
sleep 180  # Capture for 3 minutes to ensure handshake capture

echo "Handshake capture completed. Check the capture-01.cap file."
```

#### **Run this script first** and ensure that your Windows machine disconnects and reconnects to capture the handshake.

---

### 🔹 **2. Modified Bash Script for Capturing Wi-Fi Traffic (`capture_wifi_traffic.sh`)**

This version captures all traffic without stopping the `tcpdump` process or monitor mode. You'll manually stop the process when you're done.

```bash
#!/bin/bash

# Define the wireless interface and put it into monitor mode
INTERFACE="wlan0"  # Adjust if necessary
airmon-ng start $INTERFACE

# Set the monitor mode interface name
MONITOR_INTERFACE="${INTERFACE}mon"

# Start capturing traffic using tcpdump for DNS, HTTP, HTTPS, and FTP traffic
tcpdump -i $MONITOR_INTERFACE port 53 or port 80 or port 443 or port 21 -w captured_traffic.pcap

# The script will continue running until you stop it manually (Ctrl+C)
```

#### **Run this script second** and let it continue capturing traffic until you’re ready to stop it manually using `Ctrl+C`.

---

### 🔹 **3. PowerShell Script for Simulating Traffic (`SimulateWiFiTraffic.ps1`)**

This script generates network traffic from your Windows machine.

```powershell
# PowerShell script to simulate unencrypted and encrypted traffic

# Function to simulate HTTP POST request
function Send-HttpRequest {
    $url = "http://example.com/login"
    $username = "testuser"
    $password = "password123"
    $body = "username=$username&password=$password"
    
    Invoke-WebRequest -Uri $url -Method POST -Body $body
}

# Function to simulate HTTPS request
function Send-HttpsRequest {
    $url = "https://example.com/login"
    $username = "secureuser"
    $password = "securepassword123"
    $body = "username=$username&password=$password"

    Invoke-WebRequest -Uri $url -Method POST -Body $body
}

# Function to simulate FTP traffic
function Send-FTPRequest {
    $ftpServer = "ftp.example.com"
    $ftpUser = "ftpuser"
    $ftpPass = "ftppassword123"
    $filePath = "C:\\Users\\Public\\testfile.txt"
    
    # Create a simple text file to upload
    Set-Content -Path $filePath -Value "This is a test file."
    $webclient = New-Object System.Net.WebClient
    $webclient.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
    $webclient.UploadFile("ftp://$ftpServer/testfile.txt", $filePath)
}

# Function to simulate DNS requests
function Send-DNSQueries {
    $domains = @("example.com", "testsite.com", "mytestdomain.com")
    foreach ($domain in $domains) {
        nslookup $domain | Out-Null
        Start-Sleep -Seconds 2
    }
}

# Execute all traffic simulations
Send-HttpRequest
Start-Sleep -Seconds 5
Send-HttpsRequest
Start-Sleep -Seconds 5
Send-FTPRequest
Start-Sleep -Seconds 5
Send-DNSQueries
```

#### **Run this script on your Windows machine after reconnecting to the network** to simulate traffic that your Kali machine will capture.

---

### 🔹 **4. Bash Script for Analyzing Traffic (`analyze_traffic.sh`)**

This script opens the captured `.pcap` file with Wireshark for analysis. This script doesn't crack the handshake but helps you analyze the captured data effectively.

```bash
#!/bin/bash

# Open the captured traffic file in Wireshark for analysis
wireshark captured_traffic.pcap
```

#### **Run this script last** once you’ve captured sufficient traffic and are ready to analyze the data.

### 🔹 **Summary of the Correct Process**

1. **Run `capture_handshake.sh`**: Capture the WPA2 handshake. Manually reconnect your Windows machine to the Wi-Fi during this period.
2. **Run `capture_wifi_traffic.sh`**: Start capturing all network traffic. Let it run continuously until you’re finished.
3. **Run `SimulateWiFiTraffic.ps1`** on your Windows machine to generate traffic.
4. **Run `analyze_traffic.sh`** to analyze the captured traffic using Wireshark.

By removing the stopping processes in the second script, you now have a continuous capture until you manually end it, ensuring that all simulated traffic will be captured for your PoC.
# Open TCP port 1433 for default SQL Server instance
New-NetFirewallRule -DisplayName "SQL Server (TCP 1433)" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow

# Open UDP port 1434 for SQL Server Browser Service
New-NetFirewallRule -DisplayName "SQL Server Browser (UDP 1434)" -Direction Inbound -Protocol UDP -LocalPort 1434 -Action Allow

# Open dynamic port for named instance (example: 1500, replace with your actual port)
$namedInstancePort = 1500
New-NetFirewallRule -DisplayName "SQL Server Named Instance (TCP $namedInstancePort)" -Direction Inbound -Protocol TCP -LocalPort $namedInstancePort -Action Allow

# Optional: Open TCP port 1433 for outbound traffic (if required)
New-NetFirewallRule -DisplayName "SQL Server Outbound (TCP 1433)" -Direction Outbound -Protocol TCP -LocalPort 1433 -Action Allow

# Optional: Open UDP port 1434 for outbound traffic (if required)
New-NetFirewallRule -DisplayName "SQL Server Browser Outbound (UDP 1434)" -Direction Outbound -Protocol UDP -LocalPort 1434 -Action Allow

# Optional: Open dynamic port for outbound traffic for named instance (replace with your actual port)
New-NetFirewallRule -DisplayName "SQL Server Named Instance Outbound (TCP $namedInstancePort)" -Direction Outbound -Protocol TCP -LocalPort $namedInstancePort -Action Allow

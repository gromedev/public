#!/bin/bash
# Author tmg@venzo.com

if (systemctl -q is-active mdatp); 
then
	echo "${r}MDATP systemd service is running." && tput sgr0
	echo ---
	echo "${g}Organization ID: " && tput sgr0
	mdatp health --field org_id
	echo ---
	echo "${g}Health: " && tput sgr0
	mdatp health --field healthy
	echo ---
	echo "${g}Definition status: " && tput sgr0
	mdatp health --field definitions_status
	echo ---	
	echo "${g}Realtime Protection Status: " && tput sgr0
	mdatp health --field real_time_protection_enabled
	echo ---
		echo "${g}Fanotify active?: " && tput sgr0
	mdatp health --field real_time_protection_subsystem
	echo ---
	echo "${g}Cloud enabled: " && tput sgr0
	mdatp health --field cloud_enabled
	echo ---
	echo "${g}Tamper protection: " && tput sgr0
	mdatp health --field tamper_protection
	echo ---
	echo "${g}Network protection status: " && tput sgr0
	mdatp health --field network_protection_status
	echo ---
	curl -o /tmp/eicar.com.txt https://www.eicar.org/download/eicar.com.txt
	mdatp threat list
	echo "${r}Simulated threat(s): " && tput sgr0
	mdatp threat list
else
	echo "${r}MDATP service is NOT running!!!"
	echo "grep 'postinstall end' from: sudo journalctl --no-pager | grep 'microsoft-mdatp' > /home/installation.log"
	echo "and /var/log/microsoft/mdatp/install.log"
	echo ---
	echo "Refer to troubleshooting section in guide."
	tput sgr0
fi
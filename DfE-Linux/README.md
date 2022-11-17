Defender for Endpoint on Linux

Requirements

**Operating System**

+---+---------------------------------------------+
| • | > Red Hat Enterprise Linux 7.2 or higher    |
+===+=============================================+
| • | > CentOS 7.2 or higher                      |
+---+---------------------------------------------+
| • | > Ubuntu 16.04 LTS or higher LTS            |
+---+---------------------------------------------+
| • | > Debian 9 or higher                        |
+---+---------------------------------------------+
| • | > SUSE Linux Enterprise Server 12 or higher |
+---+---------------------------------------------+
| • | > Oracle Linux 7.2 or higher                |
+---+---------------------------------------------+

**Hardware**

+---+-------------------------------------+
| • | > Disk space: 1 GB                  |
+===+=====================================+
| • | > Cores: 2 minimum, 4 preferred     |
+---+-------------------------------------+
| • | > Memory: 1 GB minimum, 4 preferred |
+---+-------------------------------------+

**NO OTHER ANTIVIRUS MUST BE INSTALLED**

1

Installation\
**Author: Thomas Martin Grome -- thomas\@grome.dev**

**Make sure you use the correct package**

Please mind that the package you are installing matches the host
distribution and version.

+---+--------------------------------+
| • | > **Confirming OS versions:**\ |
|   | > oUbuntu: lsb_release -a      |
+---+--------------------------------+

CentOS: cat /etc/centos-release

All scripts must be set to executable (chmod +x) and run as sudo.

**Step 1:** Run 1PrelimInstall.sh

Depending on the distribution and version -- you may have to modify the
preliminary installation script:

![](vertopal_2fe6176bb9434b7b907da70a908f069e/media/image1.png){width="6.268054461942257in"
height="1.6875in"}

> •Ubuntu = Distribution\
> •20.04 = Distro version\
> •prod.list = software package download source. Recommend you use prod
> releases.
>
> •apt-get = Ubuntu, Debian

Refer to

The package will be automatically retrieved from e.g. Ubuntu:

> o

**Step 2:** Run 2MicrosoftDefenderATPOnboardingLinuxServer.py

2

This is the onboarding script that will connect the Linux server to
Defender for Endpoint. Do not modify it.

**Step 3:** Run 3HealthCheck.sh

This step is optional but recommended. If the script reports that the
mdatp service is not running -- then please refer to the troubleshooting
section.

**Step 4:** Run 4mde_linux_edr_diy.sh

This step is optional but recommended. Tests EDR functionality:

  ---------------------------------------------------------------------------------------------------------------------------
  ![](vertopal_2fe6176bb9434b7b907da70a908f069e/media/image2.png){width="6.268054461942257in" height="4.648611111111111in"}
  ---------------------------------------------------------------------------------------------------------------------------

3

Updating/Uninstalling DfE on Linux

Each version of Defender for Endpoint on Linux has an expiration date,
after which it will no longer continue to protect your device. You must
update the product prior to this date. To check the expiration date, run
the following command:

mdatp health \--field product_expiration

**For automatic updating**

+---+-----------------------------------------------------------------+
| • | > Requires a cron job                                           |
+===+=================================================================+
| • | https://docs.microsoft.                                         |
|   | com/en-us/microsoft-365/security/defender-endpoint/linux-update |
+---+-----------------------------------------------------------------+
|   | > mde-linux?view=o365-worldwide                                 |
+---+-----------------------------------------------------------------+

**Updating**

Debian Ubuntu: sudo apt-get install \--only-upgrade mdatp

RHEL and Centos: sudo yum update mdatp

**Uninstall**

sudo apt-get purge mdatp

4

Troubleshooting

+---+-----------------------------------------------------------------+
| • | • /opt/microsoft/mdatp/sbin/wdavdaemon requires executable      |
|   | permission (-rwxrwxr-x)                                         |
+===+=================================================================+
| • | > Network connection Fast test                                  |
+---+-----------------------------------------------------------------+
| • | > curl -w \' %{url_effective}\\n\'                              |
|   | > \'https://x.cp.wd.microsoft.com/api/report\'                  |
+---+-----------------------------------------------------------------+
|   | > \'https://cdn.x.cp.wd.microsoft.com/ping\'                    |
+---+-----------------------------------------------------------------+
|   | > Audit framework (auditd) must be enabled                      |
+---+-----------------------------------------------------------------+
| • | > Post install: mdatp health \--field                           |
|   | > real_time_protection_subsystem                                |
+---+-----------------------------------------------------------------+
|   | > Running Defender for Endpoint on Linux side by side with      |
|   | > **other fanotify-based security**                             |
+---+-----------------------------------------------------------------+
| • | > **solutions is not supported.** It can lead to unpredictable  |
|   | > results, including hanging the                                |
+---+-----------------------------------------------------------------+
|   | > operating system.                                             |
+---+-----------------------------------------------------------------+
|   | > Check if the mdatp service is running: systemctl status mdatp |
+---+-----------------------------------------------------------------+
| • | > Check if \"mdatp\" user exists id \"mdatp\"                   |
+---+-----------------------------------------------------------------+
| • | > If there\'s no output, run sudo useradd \--system             |
|   | > \--no-create-home \--user-group \--shell                      |
+---+-----------------------------------------------------------------+
| • | > /usr/sbin/nologin mdatp                                       |
+---+-----------------------------------------------------------------+
|   | > Try enabling and restarting the service using:                |
+---+-----------------------------------------------------------------+

> osudo systemctl enable mdatp\
> osudo systemctl restart mdatp
>
> • If mdatp.service isn\'t found upon running the previous command,
> run:
>
> osudo cp /opt/microsoft/mdatp/conf/mdatp.service \<systemd_path\>\
> owhere \<systemd_path\> is /lib/systemd/system for Ubuntu and Debian
> distributions
>
> and /usr/lib/systemd/system for Rhel, CentOS, Oracle and SLES.
>
> oThen rerun step 2.
>
> • Cloud connectivity problems mdatp connectivity test\
> oexpected output:\
> oTesting connection with https://cdn.x.cp.wd.microsoft.com/ping \...
> \[OK\] oTesting connection with
> https://eu-cdn.x.cp.wd.microsoft.com/ping \... \[OK\] oTesting
> connection with https://wu-cdn.x.cp.wd.microsoft.com/ping \... \[OK\]
> oEtc.
>
> oIf the connectivity test fails, check if the device has Internet
> access and if any of the

endpoints required by the product are blocked by a proxy or firewall.

5

> oList of endpoints:
>
> oFailures with curl error 35 or 60, indicate certificate pinning
> rejection. Please check if
>
> the connection is under SSL or HTTPS inspection. If so, add Microsoft
> Defender for Endpoint to the allow list.

6

Onboarding Sentinel

wget https://raw.githubusercontent.com/Microsoft/OMS-Agent-for-\
Linux/master/installer/scripts/onboard_agent.sh && sh onboard_agent.sh
-w 088a6743-51b6-4bcc-977c-6a9dd6fc59ce -s\
yGeoCjRhWkEWVMoAyxDT5c2fmKkWdKs9AfrO9mHbfJlW7SLhHxvHsBVxB3Cx5TnDczLdbMOOQtu9d
2GCd0rgdQ== -d opinsights.azure.com

![](vertopal_2fe6176bb9434b7b907da70a908f069e/media/image3.png){width="6.268054461942257in"
height="1.2805544619422573in"}

sudo cp -r /etc/audit/rules.d /etc/audit/rules.d.backup sudo nano
/etc/audit/rules.d/audit.rules\
sudo ls /etc/init.d

![](vertopal_2fe6176bb9434b7b907da70a908f069e/media/image4.png){width="6.268054461942257in"
height="4.351388888888889in"}

7

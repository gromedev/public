#!/bin/bash
#Author: Thomas Martin Grome - thomas@grome.dev
sudo yum install yum-utils
sudo yum-config-manager --add-repo=https://packages.microsoft.com/config/rhel/7.0/prod.repo
sudo rpm --import http://packages.microsoft.com/keys/microsoft.asc
yum makecache
sudo yum update
sudo yum --enablerepo=packages-microsoft-com-prod install mdatp
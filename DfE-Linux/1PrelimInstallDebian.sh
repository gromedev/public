#!/bin/bash
#Author: Thomas Martin Grome - thomas@grome.dev
sudo apt-get --yes --force-yes install curl
sudo apt-get --yes --force-yes  install libplist-utils
curl -o microsoft.list https://packages.microsoft.com/config/ubuntu/18.04/prod.list
sudo mv ./microsoft.list /etc/apt/sources.list.d/microsoft-prod.list
sudo apt-get --yes --force-yes install gpg
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
sudo apt-get --yes --force-yes  install apt-transport-https
sudo apt-get --yes --force-yes update
sudo apt-get --yes --force-yes install mdatp
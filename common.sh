#!/bin/bash

# common.sh
#
# Authors: Kevin Jackson (kevin@linuxservices.co.uk)
#          Cody Bunch (bunchc@gmail.com)
#
# Sets up common bits used in each build script.
#

export DEBIAN_FRONTEND=noninteractive

# Setup Proxy
export APT_PROXY="172.16.0.110"
export APT_PROXY_PORT=3142
#APT_PROXY="192.168.1.1"
#APT_PROXY_PORT=3128
#
# If you have a proxy outside of your VirtualBox environment, use it
if [[ ! -z "$APT_PROXY" ]]
then
	echo 'Acquire::http { Proxy "http://'${APT_PROXY}:${APT_PROXY_PORT}'"; };' | sudo tee /etc/apt/apt.conf.d/01apt-cacher-ng-proxy
fi


sudo apt-get update
apt-get -y upgrade
apt-get -y install curl openssh-server linux-headers-`uname -r`

#
# WARNING: Insecure Root Key Access and Root Password In Clear!
#

# Each machine will have same authorized_keys and private key for root access
sudo mkdir -p /root/.ssh
sudo chmod 0700 /root/.ssh

sudo cp /vagrant/id_rsa /root/.ssh
sudo cp /vagrant/id_rsa.pub /root/.ssh
sudo cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
sudo chmod 0600 /root/.ssh/*

# Fudge passwd
echo root:openstack | sudo chpasswd

# Write out hosts file
echo "
172.16.0.199 chef.rpc chef
172.16.0.200 controller.rpc controller
172.16.0.201 network.rpc network
172.16.0.202 compute.rpc compute" | sudo tee -a /etc/hosts

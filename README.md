VagrantRPC
==========

Unofficial vagrant scripts to create a Rackspace Private Cloud (http://www.rackspace.com/cloud/private/) running under VirtualBox using the Rackspace Private Cloud scripted tools.

Author :: Kevin Jackson @itarchitectkev kevin.jackson AT rackspace.co.uk

What you will need
==================
* A computer with at least 8Gb Ram
* VirtualBox (http://www.virtualbox.org/) Tested on 4.2.12 on Mac OSX
* Vagrant (http://www.vagrantup) Tested on 1.1.5 on Mac OSX


Instructions
============
	
	git clone https://github.com/bigcloudsolutions/VagrantRPC.git
	cd VagrantRPC
	vagrant up


Environment
===========

Network Interfaces
* eth0 (nat) / Default GW
* eth1 Data/Provider Network (where your SDN environment is)
* eth2 Host Network (where your VirtualBox hosts live)

Networks
* controller: eth0 (nat), eth1 (Neutron Provider), eth2 (172.16.0.200/16)
* compute: eth0 (nat), eth1 (Neutron Provider), eth2 (172.16.0.202/16)

Interfaces
* Horizon: http://172.16.0.200/    username: admin | password: openstack

Accessing Nodes
===============
To access controller and compute:

	vagrant ssh controller
	vagrant ssh compute

Root access: 

	sudo -i


Using your Rackspace Private Cloud
==================================
Log into Horizon using: admin / openstack

Perform commands on controller:

	vagrant ssh controller
	. openrc

Creating a network (example):

	neutron net-create --provider:physical_network=ph-eth1 --provider:network_type=vlan --provider:segmentation_id=100 demoNet1
	neutron subnet-create --name demoSubnet1 demoNet1 10.0.0.0/24

VagrantRPC
==========

Vagrant scripts for Rackspace Private Cloud

Author::Kevin Jackson (kevin.jackson@rackspace.co.uk)

Instructions
============
* git clone https://github.com/uksysadmin/VagrantRPC.git
* cd VagrantRPC
* vagrant up

Environment
===========

* eth0 (nat) / Default GW
* eth1 Data/Provider Network (where your SDN environment is)
* eth2 Host Network (where your VirtualBox hosts live)

chef: eth0 (nat), eth1 (unused), eth2 (172.16.0.199/16)
controller: eth0 (nat), eth1 (unused), eth2 (172.16.0.200/16)
network: eth0 (nat), eth1 (Data), eth2 (172.16.0.201/16)
compute: eth0 (nat), egh1 (Data), eth2 (172.16.0.202/16)

Horizon: http://172.16.0.200/    username: admin | password: secrete
Chef: http://172.16.0.199/       username/password (in /etc/chef-server/chef.rb)

Accessing Nodes
===============
To access chef, controller, network and compute:

vagrant ssh chef
vagrant ssh controller
vagrant ssh network
vagrant compute

Root access: sudo -i

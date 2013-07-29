# chef.sh
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y upgrade
apt-get -y install curl openssh-server linux-headers-`uname -r`

curl -s -L https://raw.github.com/rcbops/support-tools/master/chef-install/install-chef-server.sh > install-chef-server.sh

# Little hack for this VirtualBox env, assumes Chef is on interface that has default gw
# In Vagrant/VirtualBox, this is our NAT interface, eth0. We need this to be on eth2.
sed -i 's/^PRIMARY_INTERFACE.*/PRIMARY_INTERFACE=eth2/g' install-chef-server.sh
chmod +x install-chef-server.sh
bash ./install-chef-server.sh

curl -s -L https://raw.github.com/rcbops/support-tools/master/chef-install/install-cookbooks.sh | bash

# Each machine will have same authorized_keys and private key
if [[ -f /vagrant/id_rsa ]]
then
  mkdir --mode=0700 /root/.ssh
  cp /vagrant/id_rsa* /root/.ssh
  cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
  chmod 0600 /root/.ssh/*
else
  ssh-keygen -t rsa -N "" -f id_rsa
  cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
  cp /root/.ssh/* /vagrant
fi
  

# Fudge passwd
echo root:openstack | chpasswd

# No prompts when ssh
echo "
BatchMode yes
CheckHostIP no
StrictHostKeyChecking no " | sudo tee -a /root/.ssh/config
sudo chmod 0600 /root/.ssh/config

# Write out hosts file
echo "
172.16.0.199 chef.rpc chef
172.16.0.200 controller.rpc controller
172.16.0.201 network.rpc network
172.16.0.202 compute.rpc compute" | tee -a /etc/hosts

NODES="controller \
network \
compute"

#for a in ${NODES}
#do
#  ssh-copy-id root@${a}
#done

curl -skS https://raw.github.com/rcbops/support-tools/master/chef-install/install-chef-client.sh > install-chef-client.sh

chmod +x install-chef-client.sh

# Little hack for this VirtualBox env, assumes Chef is on interface that has default gw
# In Vagrant/VirtualBox, this is our NAT interface, eth0. We need this to be on eth2.
sed -i 's/^PRIMARY_INTERFACE.*/PRIMARY_INTERFACE=eth2/g' install-chef-client.sh

for a in ${NODES}
do
  sudo ./install-chef-client.sh ${a}
done

# Create environment
knife environment from file /vagrant/grizzly.json

knife exec -E 'nodes.transform("chef_environment:_default") \
  { |n| n.chef_environment("grizzly") }'

knife node run_list add controller.rpc 'role[single-controller]'
knife node run_list add network.rpc 'role[single-network-node]'
knife node run_list add compute.rpc 'role[single-compute]'

# Run Chef Client on each
# Controller
sudo ssh controller "chef-client"

# Network
sudo ssh network "chef-client"
sudo ssh network "ifdown eth1"
sudo ssh network "ifconfig eth1 0.0.0.0 up&&sudo ip link set eth1 promisc on"
sudo ssh network "ovs-vsctl add-port br-eth1 eth1"

sudo ssh network "update-rc.d -f openvswitch-switch remove"
sudo ssh network "update-rc.d openvswitch-switch stop 20 0 1 6 . start 19 2 3 4 5 ."

# Compute
sudo ssh network "chef-client"
sudo ssh network "ifdown eth1"
sudo ssh network "ifconfig eth1 0.0.0.0 up&&sudo ip link set eth1 promisc on"
sudo ssh network "ovs-vsctl add-port br-eth1 eth1"

sudo ssh network "update-rc.d -f openvswitch-switch remove"
sudo ssh network "update-rc.d openvswitch-switch stop 20 0 1 6 . start 19 2 3 4 5 ."

# chef.sh

# Source in common env vars
. /vagrant/common.sh

curl -s -L https://raw.github.com/rcbops/support-tools/master/chef-install/install-chef-server.sh > install-chef-server.sh

# Little hack for this VirtualBox env, assumes Chef is on interface that has default gw
# In Vagrant/VirtualBox, this is our NAT interface, eth0. We need this to be on eth2.
sed -i 's/^PRIMARY_INTERFACE.*/PRIMARY_INTERFACE=eth2/g' install-chef-server.sh
chmod +x install-chef-server.sh
bash ./install-chef-server.sh

curl -s -L https://raw.github.com/rcbops/support-tools/master/chef-install/install-cookbooks.sh | bash

# No prompts when ssh
echo "
BatchMode yes
CheckHostIP no
StrictHostKeyChecking no " | sudo tee -a /root/.ssh/config
sudo chmod 0600 /root/.ssh/config

NODES="controller \
network \
compute"

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


knife node run_list add controller.rpc 'role[single-controller]'
knife node run_list add network.rpc 'role[single-network-node]'
knife node run_list add compute.rpc 'role[single-compute]'

knife exec -E 'nodes.transform("chef_environment:_default") { |n| n.chef_environment("grizzly") }'

# Run Chef Client on each
# Controller
sudo ssh controller "chef-client"
sudo ssh controller "chef-client"

# Network
sudo ssh network "chef-client"
sudo ssh network "ifdown eth1"
sudo ssh network "ifconfig eth1 0.0.0.0 up&&sudo ip link set eth1 promisc on"
sudo ssh network "ovs-vsctl add-port br-eth1 eth1"

sudo ssh network "update-rc.d -f openvswitch-switch remove"
sudo ssh network "update-rc.d openvswitch-switch stop 20 0 1 6 . start 19 2 3 4 5 ."

# Compute
sudo ssh compute "chef-client"
sudo ssh compute "ifdown eth1"
sudo ssh compute "ifconfig eth1 0.0.0.0 up&&sudo ip link set eth1 promisc on"
sudo ssh compute "ovs-vsctl add-port br-eth1 eth1"

sudo ssh compute "update-rc.d -f openvswitch-switch remove"
sudo ssh compute "update-rc.d openvswitch-switch stop 20 0 1 6 . start 19 2 3 4 5 ."

# Some workarounds - run chef-again
sudo ssh controller "chef-client"
sudo ssh network "chef-client"
sudo ssh compute "chef-client"


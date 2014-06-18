# controller.sh
set -ex

# Rabbit Password
RMQ_PW="Passw0rd"

# Rabbit IP address, this should be the host ip which is on
# the same network used by your management network
RMQ_IP="172.16.0.200"

# Set the cookbook version that we will upload to chef
COOKBOOK_VERSION="v4.2.2"

# SET THE NODE IP ADDRESSES
CONTROLLER1=$RMQ_IP

# This is the VIP prefix, IE the beginning of your IP addresses for all your VIPS.
# Note, This makes a lot of assumptions for your VIPS.
# The environment use .241, .242, .243 for your HA VIPS.
VIP_PREFIX="172.16.0"

export CHEF_SERVER_URL=https://localhost:4000

# Source in common env vars
. /vagrant/common.sh

function install_required_packages()
{
    apt-get update
    apt-get install -y python-dev python-pip git erlang erlang-nox erlang-dev curl lvm2
    # pip install git+https://github.com/cloudnull/mungerator
    RABBIT_URL="http://www.rabbitmq.com"
}

function erlang_cookie() {
    mkdir -p /var/lib/rabbitmq
    echo -n "AnyAlphaNumericStringWillDo" > /var/lib/rabbitmq/.erlang.cookie
    chmod 600 /var/lib/rabbitmq/.erlang.cookie
}

function setup_rabbit() {
    if [ ! "$(rabbitmqctl list_vhosts | grep -w '/chef')" ];then
      rabbitmqctl add_vhost /chef
    fi

    if [ "$(rabbitmqctl list_users | grep -w 'chef')" ];then
      rabbitmqctl delete_user chef
    fi

    rabbitmqctl add_user chef "${RMQ_PW}"
    rabbitmqctl set_permissions -p /chef chef '.*' '.*' '.*'
}

function install_rabbit() {
    RABBITMQ_KEY="${RABBIT_URL}/rabbitmq-signing-key-public.asc"
    wget -O /tmp/rabbitmq.asc ${RABBITMQ_KEY};
    apt-key add /tmp/rabbitmq.asc
    RABBITMQ="${RABBIT_URL}/releases/rabbitmq-server/v3.1.5/rabbitmq-server_3.1.5-1_all.deb"
    wget -O /tmp/rabbitmq.deb ${RABBITMQ}
    dpkg -i /tmp/rabbitmq.deb
}

function install_chef_server() {
    CHEF="https://www.opscode.com/chef/download-server?p=ubuntu&pv=12.04&m=x86_64"
    CHEF_SERVER_PACKAGE_URL="${CHEF}"
    wget -O /tmp/chef_server.deb ${CHEF_SERVER_PACKAGE_URL}
    dpkg -i /tmp/chef_server.deb

    ln -sf /opt/chef-server/embedded/bin/knife /usr/bin/knife
    ln -sf /opt/chef-server/embedded/bin/ohai /usr/bin/ohai
}

function configure_chef_server() {
    mkdir -p /etc/chef-server
    cat > /etc/chef-server/chef-server.rb <<EOF
erchef["s3_url_ttl"] = 3600
nginx["ssl_port"] = 4000
nginx["non_ssl_port"] = 4080
nginx["enable_non_ssl"] = true
rabbitmq["enable"] = false
rabbitmq["password"] = "${RMQ_PW}"
rabbitmq["vip"] = "${RMQ_IP}"
rabbitmq['node_ip_address'] = "${RMQ_IP}"
rabbitmq['node_port'] = 5672
chef_server_webui["web_ui_admin_default_password"] = "openstack"
bookshelf["url"] = "https://172.16.0.200:4000"
EOF

    chef-server-ctl reconfigure

}

function install_chef_client() {
    export CHEF_SERVER_URL=https://localhost:4000

    # Configure Knife
    mkdir -p /root/.chef
    cat > /root/.chef/knife.rb <<EOF
log_level                :info
log_location             STDOUT
node_name                'admin'
client_key               '/etc/chef-server/admin.pem'
validation_client_name   'chef-validator'
validation_key           '/etc/chef-server/chef-validator.pem'
chef_server_url          "https://localhost:4000"
cache_options( :path => '/root/.chef/checksums' )
cookbook_path            [ '/opt/chef-cookbooks/cookbooks' ]
EOF
}

function install_cookbooks() {
    mkdir -p /opt/

    if [ -d "/opt/chef-cookbooks" ];then
        rm -rf /opt/chef-cookbooks
    fi

    git clone https://github.com/rcbops/chef-cookbooks.git /opt/chef-cookbooks
    pushd /opt/chef-cookbooks
    git checkout ${COOKBOOK_VERSION}
    git submodule init
    git submodule sync
    git submodule update


    # Upload all of the RCBOPS Cookbooks
    knife cookbook upload -o /opt/chef-cookbooks/cookbooks -a
    popd
}

function setup_ssh() {
    # No prompts when ssh
    echo "
    BatchMode yes
    CheckHostIP no
    StrictHostKeyChecking no " | sudo tee -a /root/.ssh/config
    sudo chmod 0600 /root/.ssh/config
}

function configure_environment() {
    # Save the erlang cookie
    if [ ! -f "/var/lib/rabbitmq/.erlang.cookie" ];then
        ERLANG_COOKIE="ANYSTRINGWILLDOJUSTFINE"
    else
        ERLANG_COOKIE="$(cat /var/lib/rabbitmq/.erlang.cookie)"
    fi

    # DROP THE BASE ENVIRONMENT FILE
    cat > /opt/base.env.json <<EOF
{
  "name": "rpcs",
  "description": "Environment for Openstack Private Cloud",
  "cookbook_versions": {
  },
  "json_class": "Chef::Environment",
  "chef_type": "environment",
  "default_attributes": {
  },
  "override_attributes": {
    "monitoring": {
      "procmon_provider": "monit",
      "metric_provider": "collectd"
    },
    "enable_monit": true,
    "osops_networks": {
      "management": "${VIP_PREFIX}.0/24",
      "swift": "${VIP_PREFIX}.0/24",
      "public": "${VIP_PREFIX}.0/24",
      "nova": "${VIP_PREFIX}.0/24"
    },
    "rabbitmq": {
      "open_file_limit": 4096,
      "use_distro_version": false
    },
    "nova": {
      "config": {
        "use_single_default_gateway": false,
        "ram_allocation_ratio": 1.0,
        "disk_allocation_ratio": 1.0,
        "cpu_allocation_ratio": 2.0,
        "resume_guests_state_on_host_boot": true,
        "force_config_drive": true
      },
      "network": {
        "provider": "neutron"
      },
      "scheduler": {
        "default_filters": [
          "AvailabilityZoneFilter",
          "ComputeFilter",
          "RetryFilter"
        ]
      },
      "libvirt": {
        "vncserver_listen": "0.0.0.0",
        "virt_type": "qemu"
      }
    },
    "keystone": {
      "pki": {
        "enabled": false
      },
      "admin_user": "admin",
      "tenants": [
        "service",
        "admin",
        "demo",
        "demo2"
      ],
      "users": {
        "admin": {
          "password": "secrete",
          "roles": {
            "admin": [
              "admin"
            ]
          }
        },
        "demo": {
          "password": "secrete",
          "default_tenant": "demo",
          "roles": {
            "Member": [
              "demo2",
              "demo"
            ]
          }
        },
        "demo2": {
          "password": "secrete",
          "default_tenant": "demo2",
          "roles": {
            "Member": [
              "demo2",
              "demo"
            ]
          }
        }
      }
    },
    "neutron": {
      "ovs": {
        "external_bridge": "",
        "network_type": "gre",
        "provider_networks": [
          {
            "bridge": "br-eth1",
            "vlans": "1024:1024",
            "label": "ph-eth1"
          }
        ]
      }
    },
    "mysql": {
      "tunable": {
        "log_queries_not_using_index": false
      },
      "allow_remote_root": true,
      "root_network_acl": "127.0.0.1"
    },
    "vips": {
      "horizon-dash": "${VIP_PREFIX}.243",
      "keystone-service-api": "${VIP_PREFIX}.243",
      "nova-xvpvnc-proxy": "${VIP_PREFIX}.243",
      "nova-api": "${VIP_PREFIX}.243",
      "nova-metadata-api": "${VIP_PREFIX}.243",
      "cinder-api": "${VIP_PREFIX}.243",
      "nova-ec2-public": "${VIP_PREFIX}.243",
      "config": {
        "${VIP_PREFIX}.243": {
          "vrid": 12,
          "network": "public"
        },
        "${VIP_PREFIX}.241": {
          "vrid": 10,
          "network": "public"
        },
        "${VIP_PREFIX}.242": {
          "vrid": 11,
          "network": "public"
        }
      },
      "rabbitmq-queue": "${VIP_PREFIX}.242",
      "nova-novnc-proxy": "${VIP_PREFIX}.243",
      "mysql-db": "${VIP_PREFIX}.241",
      "glance-api": "${VIP_PREFIX}.243",
      "keystone-internal-api": "${VIP_PREFIX}.243",
      "horizon-dash_ssl": "${VIP_PREFIX}.243",
      "glance-registry": "${VIP_PREFIX}.243",
      "neutron-api": "${VIP_PREFIX}.243",
      "ceilometer-api": "${VIP_PREFIX}.243",
      "ceilometer-central-agent": "${VIP_PREFIX}.243",
      "heat-api": "${VIP_PREFIX}.243",
      "heat-api-cfn": "${VIP_PREFIX}.243",
      "heat-api-cloudwatch": "${VIP_PREFIX}.243",
      "keystone-admin-api": "${VIP_PREFIX}.243"
    },
    "glance": {
      "images": [
        "cirros"
      ],
      "image" : {
        "cirros": "https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-x86_64-disk.img"
      },
      "image_upload": false
    },
    "osops": {
      "do_package_upgrades": false,
      "apply_patches": false
    },
    "developer_mode": false
  }
}
EOF

    # Upload all of the RCBOPS Roles
    knife role from file /opt/chef-cookbooks/roles/*.rb
    knife environment from file /opt/base.env.json
}

function install_controllers_ha() {
    # Build all the things
    knife bootstrap localhost -E rpcs -r 'role[ha-controller1],role[single-network-node]' --server-url $CHEF_SERVER_URL

    chef-client
    # Configure Rabbit HA Policy
    knife ssh -C1 -a ipaddress 'role:*controller*' "rabbitmqctl set_policy ha-all '.*' '{\"ha-mode\":\"all\", \"ha-sync-mode\":\"automatic\"}' 0"
    chef-client
}

function install_computes() {
    knife bootstrap compute.rpc -E rpcs -r 'role[single-compute]' --server-url https://172.16.0.200:4000

    sleep 15 # Give Solr a chance to do some indexing so we can search

    knife ssh "role:single-compute" chef-client
}

function neutron_interface() {

    ifdown eth1
    ifconfig eth1 0.0.0.0 up&&sudo ip link set eth1 promisc on

    sudo ssh compute "ifdown eth1"
    sudo ssh compute "ifconfig eth1 0.0.0.0 up&&sudo ip link set eth1 promisc on"
    sudo ssh compute "ovs-vsctl add-port br-eth1 eth1"

}

function ovs_bridge() {
	knife ssh "role:*" "ovs-vsctl add-port br-eth1 eth1"
	chef-client
	sudo ssh compute "chef-client"	
}

function sys_tuning() {
    sysctl net.ipv4.conf.default.rp_filter=0 | tee -a /etc/sysctl.conf
    sysctl net.ipv4.conf.all.rp_filter=0 | tee -a /etc/sysctl.conf
    sysctl net.ipv4.ip_forward=1 | tee -a /etc/sysctl.conf

    # echo "vhost_net" >> /etc/modules.conf
}

install_required_packages
erlang_cookie
install_rabbit
setup_rabbit
install_chef_server
configure_chef_server
install_chef_client
install_cookbooks
setup_ssh
configure_environment
install_controllers_ha
install_computes
neutron_interface
ovs_bridge
sys_tuning

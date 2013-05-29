#
# Cookbook Name:: bcpc
# Recipe:: networking
#
# Copyright 2013, Bloomberg L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "bcpc::default"

ruby_block "initialize-ssh-keys" do
    block do
        make_config('ssh-private-key', %x[printf 'y\n' | ssh-keygen -t rsa -N '' -q -f /dev/stdout | sed -e '1,1d' -e 's/.*-----BEGIN/-----BEGIN/'])
        make_config('ssh-public-key', %x[echo "#{get_config('ssh-private-key')}" | ssh-keygen -y -f /dev/stdin])
        if get_config('ssl-certificate').nil? then
            temp = %x[openssl req -new -x509 -passout pass:temp_passwd -newkey rsa:4096 -out /dev/stdout -keyout /dev/stdout -days 1095 -subj "/C=US/ST=NY/L=New York/O=Bloomberg/OU=#{node[:bcpc][:region_name]}/CN=#{node[:bcpc][:domain_name]}/emailAddress=#{node[:bcpc][:admin_email]}"]
            make_config('ssl-private-key', %x[echo "#{temp}" | openssl rsa -passin pass:temp_passwd -out /dev/stdout])
            make_config('ssl-certificate', %x[echo "#{temp}" | openssl x509])
        end
    end
end

directory "/root/.ssh" do
    owner "root"
    group "root"
    mode 00700
end

template "/root/.ssh/authorized_keys" do
    source "authorized_keys.erb"
    owner "root"
    group "root"
    mode 00644
end

template "/root/.ssh/id_rsa" do
    source "id_rsa.erb"
    owner "root"
    group "root"
    mode 00600
end

template "/etc/ssl/certs/ssl-bcpc.pem" do
    source "ssl-bcpc.pem.erb"
    owner "root"
    group "root"
    mode 00644
end

template "/etc/ssl/private/ssl-bcpc.key" do
    source "ssl-bcpc.key.erb"
    owner "root"
    group "root"
    mode 00600
end

template "/etc/hosts" do
    source "hosts.erb"
    mode 00644
    variables( :servers => get_all_nodes )
end

template "/etc/ssh/sshd_config" do
    source "sshd_config.erb"
    mode 00644
    notifies :restart, "service[ssh]", :immediately
end

service "ssh" do
    action [ :enable, :start ]
end

service "cron" do
    action [ :enable, :start ]
end

# Core networking package
package "vlan"

# Useful system tools
package "fio"
package "bc"
package "htop"
package "sysstat"
package "acpid"

# Remove spurious logging failures from this package
package "powernap" do
    action :remove
end

bash "enable-ip-forwarding" do
    user "root"
    code <<-EOH
        echo "1" > /proc/sys/net/ipv4/ip_forward
        sed --in-place '/^net.ipv4.ip_forward/d' /etc/sysctl.conf
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    EOH
    not_if "grep -e '^net.ipv4.ip_forward=1' /etc/sysctl.conf"
end

bash "enable-mellanox" do
    user "root"
    code <<-EOH
                if [ -z "`lsmod | grep mlx4_en`" ]; then
                   modprobe mlx4_en
                fi
                if [ -z "`grep mlx4_en /etc/modules`" ]; then
                   echo "mlx4_en" >> /etc/modules
                fi
    EOH
    only_if "lspci | grep Mellanox"
end

bash "enable-8021q" do
    user "root"
    code <<-EOH
        modprobe 8021q
        sed --in-place '/^8021q/d' /etc/modules
        echo '8021q' >> /etc/modules
    EOH
    not_if "grep -e '^8021q' /etc/modules"
end

bash "interface-mgmt-make-static-if-dhcp" do
    user "root"
    code <<-EOH
        sed --in-place '/\\(.*#{node[:bcpc][:management][:interface]}.*\\)/d' /etc/network/interfaces
        echo >> /etc/network/interfaces
        echo "auto #{node[:bcpc][:management][:interface]}" >> /etc/network/interfaces
        echo "iface #{node[:bcpc][:management][:interface]} inet static" >> /etc/network/interfaces
        echo "  address #{node[:bcpc][:management][:ip]}" >> /etc/network/interfaces
        echo "  netmask #{node[:bcpc][:management][:netmask]}" >> /etc/network/interfaces
        echo "  gateway #{node[:bcpc][:management][:gateway]}" >> /etc/network/interfaces
        echo "  dns-nameservers #{node[:bcpc][:dns_servers].join(' ')}" >> /etc/network/interfaces
        echo "  metric 100" >> /etc/network/interfaces
        ifup #{node[:bcpc][:management][:interface]}
    EOH
    only_if "cat /etc/network/interfaces | grep #{node[:bcpc][:management][:interface]} | grep dhcp"
end

bash "interface-storage" do
    user "root"
    code <<-EOH
        echo >> /etc/network/interfaces
        echo "auto #{node[:bcpc][:storage][:interface]}" >> /etc/network/interfaces
        echo "iface #{node[:bcpc][:storage][:interface]} inet static" >> /etc/network/interfaces
        echo "  address #{node[:bcpc][:storage][:ip]}" >> /etc/network/interfaces
        echo "  netmask #{node[:bcpc][:storage][:netmask]}" >> /etc/network/interfaces
        echo "  gateway #{node[:bcpc][:storage][:gateway]}" >> /etc/network/interfaces
        echo "  metric 300" >> /etc/network/interfaces
        ifup #{node[:bcpc][:storage][:interface]}
    EOH
    not_if "ifquery --list | grep #{node[:bcpc][:storage][:interface]}"
end

bash "interface-floating" do
    user "root"
    code <<-EOH
        echo >> /etc/network/interfaces
        echo "auto #{node[:bcpc][:floating][:interface]}" >> /etc/network/interfaces
        echo "iface #{node[:bcpc][:floating][:interface]} inet static" >> /etc/network/interfaces
        echo "  address #{node[:bcpc][:floating][:ip]}" >> /etc/network/interfaces
        echo "  netmask #{node[:bcpc][:floating][:netmask]}" >> /etc/network/interfaces
        echo "  gateway #{node[:bcpc][:floating][:gateway]}" >> /etc/network/interfaces
        echo "  metric 200" >> /etc/network/interfaces
        ifup #{node[:bcpc][:floating][:interface]}
    EOH
    not_if "ifquery --list | grep #{node[:bcpc][:floating][:interface]}"
end

bash "routing-floating" do
    user "root"
    code "echo '1 floating' >> /etc/iproute2/rt_tables"
    not_if "grep -e '^1 floating' /etc/iproute2/rt_tables"
end

bash "routing-storage" do
    user "root"
    code "echo '2 storage' >> /etc/iproute2/rt_tables"
    not_if "grep -e '^2 storage' /etc/iproute2/rt_tables"
end

template "/etc/network/if-up.d/bcpc-routing" do
    mode 00775
    source "bcpc-routing-2.erb"
    notifies :run, "execute[run-routing-script-once]", :immediately
end

execute "run-routing-script-once" do
    action :nothing
    command "/etc/network/if-up.d/bcpc-routing"
end

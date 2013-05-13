#
# Cookbook Name:: bcpc
# Recipe:: cobbler
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

# for mkpasswd
package "whois"

ruby_block "initialize-cobbler-config" do
    block do
        # don't do anything with this for now
        #make_config('cobbler-user-password', secure_password)
        make_config('cobbler-root-password', secure_password)
        make_config('cobbler-root-password-salted', %x[ printf "#{get_config('cobbler-root-password')}" | mkpasswd -s -m sha-512 ] )
    end
end

package "isc-dhcp-server"
package "cobbler"
package "cobbler-web"

template "/etc/cobbler/settings" do
    source "cobbler.settings.erb"
    mode 00644
    notifies :restart, "service[cobbler]", :delayed
end

template "/etc/cobbler/dhcp.template" do
    source "cobbler.dhcp.template.erb"
    mode 00644
    # TODO - calculate subnet from node[:bcpc][:management][:cidr]
    variables( :range => node[:bcpc][:bootstrap][:dhcp_range],
               :subnet => node[:bcpc][:bootstrap][:dhcp_subnet] )
    notifies :restart, "service[cobbler]", :delayed
end

template "/var/lib/cobbler/kickstarts/bcpc_ubuntu_host.preseed" do
    source "cobbler.bcpc_ubuntu_host.preseed.erb"
    mode 00644
    variables( :root_password => get_config('cobbler-root-password-salted') )
end

cookbook_file "/tmp/ubuntu-12.04-mini.iso" do
    source "bins/ubuntu-12.04-mini.iso"
    owner "root"
    mode 00444
end

bash "import-ubuntu-distribution-cobbler" do
    user "root"
    code <<-EOH
        mount -o loop /tmp/ubuntu-12.04-mini.iso /mnt
        cobbler import --name=ubuntu-12.04-mini --path=/mnt --breed=ubuntu --os-version=precise --arch=x86_64
        umount /mnt
        cobbler sync
    EOH
    not_if "cobbler distro list | grep ubuntu-12.04-mini"
end

bash "import-bcpc-profile-cobbler" do
    user "root"
    code <<-EOH
        cobbler profile add --name=bcpc_host --distro=ubuntu-12.04-mini-x86_64 --kickstart=/var/lib/cobbler/kickstarts/bcpc_ubuntu_host.preseed --kopts="interface=auto"
        cobbler sync
    EOH
    not_if "cobbler profile list | grep bcpc_host"
end

service "isc-dhcp-server" do
    action [ :enable, :start ]
end

service "cobbler" do
    action [ :enable, :start ]
end

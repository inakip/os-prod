#
# Cookbook Name:: bcpc
# Recipe:: nova-head
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

include_recipe "bcpc::nova-common"
include_recipe "bcpc::ceph-work"

ruby_block "initialize-nova-work-config" do
    block do
        make_config('ssh-nova-private-key', %x[printf 'y\n' | ssh-keygen -t rsa -N '' -q -f /dev/stdout | sed -e '1,1d' -e 's/.*-----BEGIN/-----BEGIN/'])
        make_config('ssh-nova-public-key', %x[echo "#{get_config('ssh-nova-private-key')}" | ssh-keygen -y -f /dev/stdin])
    end
end

package "nova-compute-#{node[:bcpc][:virt_type]}" do
    action :upgrade
end

%w{nova-api nova-network nova-compute nova-novncproxy}.each do |pkg|
    package pkg do
        action :upgrade
    end
    service pkg do
        action [ :enable, :start ]
    end
end

%w{novnc pm-utils memcached python-memcache}.each do |pkg|
    package pkg do
        action :upgrade
    end
end

bash "restart-all-nova-workers" do
    action :nothing
    subscribes :run, resources("template[/etc/nova/nova.conf]"), :delayed
    subscribes :run, resources("template[/etc/nova/api-paste.ini]"), :delayed
    notifies :restart, "service[nova-api]", :immediately
    notifies :restart, "service[nova-compute]", :immediately
    notifies :restart, "service[nova-network]", :immediately
    notifies :restart, "service[nova-novncproxy]", :immediately
end

directory "/var/lib/nova/.ssh" do
    owner "nova"
    group "nova"
    mode 00700
end

template "/var/lib/nova/.ssh/authorized_keys" do
    source "nova-authorized_keys.erb"
    owner "nova"
    group "nova"
    mode 00644
end

template "/var/lib/nova/.ssh/id_rsa" do
    source "nova-id_rsa.erb"
    owner "nova"
    group "nova"
    mode 00600
end

template "/var/lib/nova/.ssh/config" do
    source "nova-ssh_config.erb"
    owner "nova"
    group "nova"
    mode 00600
end

service "libvirt-bin" do
    action [ :enable, :start ]
end

template "/etc/nova/virsh-secret.xml" do
    source "virsh-secret.xml.erb"
    owner "nova"
    group "nova"
    mode 00600
end

bash "set-nova-user-shell" do
    user "root"
    code <<-EOH
        chsh -s /bin/bash nova
    EOH
    not_if "grep nova /etc/passwd | grep /bin/bash"
end

ruby_block 'load-virsh-keys' do
    block do
        if not system "virsh secret-list | grep -i #{get_config('libvirt-secret-uuid')}" then
            %x[ ADMIN_KEY=`ceph --name mon. --keyring /etc/ceph/ceph.mon.keyring auth get-or-create-key client.admin`
                virsh secret-define --file /etc/nova/virsh-secret.xml
                virsh secret-set-value --secret #{get_config('libvirt-secret-uuid')} \
                    --base64 "$ADMIN_KEY"
            ]
        end
    end
end

bash "remove-default-virsh-net" do
    user "root"
    code <<-EOH
        virsh net-destroy default
        virsh net-undefine default
    EOH
    only_if "virsh net-list | grep -i default"
end

bash "libvirt-device-acls" do
    user "root"
    code <<-EOH
        echo "cgroup_device_acl = [" >> /etc/libvirt/qemu.conf
        echo "   \\\"/dev/null\\\", \\\"/dev/full\\\", \\\"/dev/zero\\\"," >> /etc/libvirt/qemu.conf
        echo "   \\\"/dev/random\\\", \\\"/dev/urandom\\\"," >> /etc/libvirt/qemu.conf
        echo "   \\\"/dev/ptmx\\\", \\\"/dev/kvm\\\", \\\"/dev/kqemu\\\"," >> /etc/libvirt/qemu.conf
        echo "   \\\"/dev/rtc\\\", \\\"/dev/hpet\\\", \\\"/dev/net/tun\\\"" >> /etc/libvirt/qemu.conf
        echo "]" >> /etc/libvirt/qemu.conf
    EOH
    not_if "grep -e '^cgroup_device_acl' /etc/libvirt/qemu.conf"
    notifies :restart, "service[libvirt-bin]", :immediately
end

cookbook_file "/tmp/nova.patch" do
    source "nova.patch"
    owner "root"
    mode 00644
end

bash "patch-for-nova-bugs" do
    user "root"
    code <<-EOH
        cd /usr/lib/python2.7/dist-packages/nova
        patch -p1 < /tmp/nova.patch
        cp /tmp/nova.patch .
    EOH
    not_if "test -f /usr/lib/python2.7/dist-packages/nova/nova.patch"
end

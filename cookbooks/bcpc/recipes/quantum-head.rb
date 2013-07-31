#
# Cookbook Name:: bcpc
# Recipe:: quantum-head
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

include_recipe "bcpc::mysql"
include_recipe "bcpc::openstack"

ruby_block "initialize-quantum-config" do
    block do
        make_config('mysql-quantum-user', "quantum")
        make_config('mysql-quantum-password', secure_password)
        make_config('libvirt-secret-uuid', %x[uuidgen -r].strip)
    end
end

%w{quantum-server python-quantumclient quantum-metadata-agent quantum-dhcp-agent quantum-l3-agent quantum-plugin-linuxbridge quantum-plugin-linuxbridge-agent}.each do |pkg|
    package pkg do
        action :upgrade
    end
end

%w{quantum-server quantum-metadata-agent quantum-dhcp-agent quantum-l3-agent quantum-plugin-linuxbridge-agent}.each do |srv|
    service srv do
      provider Chef::Provider::Service::Upstart
    supports :status => true, :restart => true, :reload => true
    action [ :enable, :start ]
    end
end

bash "restart-quantum-head" do
    action :nothing
    notifies :restart, "service[quantum-server]", :immediately
    notifies :restart, "service[quantum-metadata-agent]", :immediately
    notifies :restart, "service[quantum-dhcp-agent]", :immediately
    notifies :restart, "service[quantum-l3-agent]", :immediately
    notifies :restart, "service[quantum-plugin-linuxbridge-agent]", :immediately
end

template "/etc/quantum/quantum.conf" do
    source "quantum.conf.erb"
    owner "quantum"
    group "quantum"
    mode 00644
    notifies :run, "bash[restart-quantum]", :delayed
end

template "/etc/default/quantum-server" do
    source "quantum-server.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :run, "bash[restart-quantum-head]", :delayed
end

template "/etc/quantum/plugins/linuxbridge/linuxbridge_conf.ini" do
    source "linuxbridge_conf.ini.head.erb"
    owner "quantum"
    group "quantum"
    mode 00644
    notifies :run, "bash[restart-quantum-head]", :delayed
end

template "/etc/quantum/metadata_agent.ini" do
    source "metadata_agent.ini.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :run, "bash[restart-quantum-head]", :delayed
end

template "/etc/quantum/dhcp_agent.ini" do
    source "dhcp_agent.ini.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :run, "bash[restart-quantum-head]", :delayed
end

template "/etc/quantum/l3_agent.ini" do
    source "l3_agent.ini.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :run, "bash[restart-quantum-head]", :delayed
end

ruby_block "quantum-database-creation" do
    block do
        if not system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = \"#{node['bcpc']['quantum_dbname']}\"'|grep \"#{node['bcpc']['quantum_dbname']}\"" then
            %x[ mysql -uroot -p#{get_config('mysql-root-password')} -e "CREATE DATABASE #{node['bcpc']['quantum_dbname']};"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['quantum_dbname']}.* TO '#{get_config('mysql-quantum-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-quantum-password')}';"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['quantum_dbname']}.* TO '#{get_config('mysql-quantum-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-quantum-password')}';"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "FLUSH PRIVILEGES;"
            ]
        end
    end
end


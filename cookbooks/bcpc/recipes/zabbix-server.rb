#
# Cookbook Name:: bcpc
# Recipe:: zabbix-server
#
# Copyright 2013, Bloomberg L.P.
#
# All rights reserved - Do Not Redistribute
#

include_recipe "bcpc::mysql"
include_recipe "bcpc::horizon"

ruby_block "initialize-zabbix-config" do
    block do
        make_config('mysql-zabbix-user', "zabbix")
        make_config('mysql-zabbix-password', secure_password)
        make_config('zabbix-admin-user', "admin")
        make_config('zabbix-admin-password', secure_password)
        make_config('zabbix-guest-user', "guest")
        make_config('zabbix-guest-password', secure_password)
    end
end

cookbook_file "/tmp/zabbix-server.tar.gz" do
    source "bins/zabbix-server.tar.gz"
    owner "root"
    mode 00444
end

bash "install-zabbix-server" do
    code <<-EOH
        tar zxf /tmp/zabbix-server.tar.gz -C /usr/local/
    EOH
    not_if "test -f /usr/local/sbin/zabbix_server"
end

user node[:bcpc][:zabbix][:user] do
    shell "/bin/false"
    home "/var/log"
    gid node[:bcpc][:zabbix][:group]
    system true
end

directory "/var/log/zabbix" do
    user node[:bcpc][:zabbix][:user]
    group node[:bcpc][:zabbix][:group]
    mode 00755
end

template "/etc/init/zabbix-server.conf" do
    source "upstart-zabbix-server.conf.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[zabbix-server]", :delayed
end

template "/usr/local/etc/zabbix_server.conf" do
    source "zabbix_server.conf.erb"
    owner node[:bcpc][:zabbix][:user]
    group "root"
    mode 00600
    notifies :restart, "service[zabbix-server]", :delayed
end

ruby_block "zabbix-database-creation" do
    block do
        if not system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = \"#{node['bcpc']['zabbix_dbname']}\"'|grep \"#{node['bcpc']['zabbix_dbname']}\"" then
            puts %x[ mysql -uroot -p#{get_config('mysql-root-password')} -e "CREATE DATABASE #{node['bcpc']['zabbix_dbname']} CHARACTER SET UTF8;"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['zabbix_dbname']}.* TO '#{get_config('mysql-zabbix-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-zabbix-password')}';"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['zabbix_dbname']}.* TO '#{get_config('mysql-zabbix-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-zabbix-password')}';"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "FLUSH PRIVILEGES;"
                mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['zabbix_dbname']} < /usr/local/share/zabbix/schema.sql
                mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['zabbix_dbname']} < /usr/local/share/zabbix/images.sql
                mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['zabbix_dbname']} < /usr/local/share/zabbix/data.sql
                HASH=`echo -n "#{get_config('zabbix-admin-password')}" | md5sum | awk '{print $1}'`
                mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['zabbix_dbname']} -e "UPDATE users SET passwd=\\"$HASH\\" WHERE alias=\\"#{get_config('zabbix-admin-user')}\\";"
                HASH=`echo -n "#{get_config('zabbix-guest-password')}" | md5sum | awk '{print $1}'`
                mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['zabbix_dbname']} -e "UPDATE users SET passwd=\\"$HASH\\" WHERE alias=\\"#{get_config('zabbix-guest-user')}\\";"
            ]
        end
    end
end

service "zabbix-server" do
    provider Chef::Provider::Service::Upstart
    action [ :enable, :start ]
end

%w{traceroute libapache2-mod-php5 php5-mysql php5-gd}.each do |pkg|
    package pkg do
        action :upgrade
    end
end

bash "apache-enable-php5" do
    user "root"
    code <<-EOH
        a2enmod php5
    EOH
    not_if "test -r /etc/apache2/mods-enabled/php5.load"
    notifies :restart, "service[apache2]", :delayed
end

file "/etc/php5/apache2/conf.d/bcpc.ini" do
    user "root"
    group "root"
    mode 00644
    content <<-EOH
        post_max_size = 16M
        max_execution_time = 300
        max_input_time = 300
        date.timezone = America/New_York
    EOH
    notifies :restart, "service[apache2]", :delayed
end

template "/usr/local/share/zabbix/php/conf/zabbix.conf.php" do
    source "zabbix.conf.php.erb"
    user node[:bcpc][:zabbix][:user]
    group "www-data"
    mode 00640
    notifies :restart, "service[apache2]", :delayed
end

template "/etc/apache2/conf.d/zabbix-web.conf" do
    source "apache-zabbix-web.conf.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[apache2]", :delayed
end

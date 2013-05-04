#
# Cookbook Name:: bcpc
# Recipe:: graphite
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
include_recipe "bcpc::ceph-head"

ruby_block "initialize-graphite-config" do
    block do
        make_config('mysql-graphite-user', "graphite")
        make_config('mysql-graphite-password', secure_password)
    end
end

%w{python-whisper_0.9.10_all.deb python-carbon_0.9.10_all.deb python-graphite-web_0.9.10_all.deb}.each do |pkg|
    cookbook_file "/tmp/#{pkg}" do
        source "bins/#{pkg}"
        owner "root"
        mode 00444
    end

    package "#{pkg}" do
        provider Chef::Provider::Package::Dpkg
        source "/tmp/#{pkg}"
        action :install
    end
end

%w{apache2 python-pip python-cairo python-django python-django-tagging python-ldap python-twisted python-memcache libapache2-mod-wsgi libapache2-mod-python}.each do |pkg|
        package pkg do
            action :upgrade
        end
end

template "/opt/graphite/conf/carbon.conf" do
    source "carbon.conf.erb"
    owner "root"
    group "root"
    mode 00644
    variables( :servers => get_head_nodes,
               :min_quorum => get_head_nodes.length/2 + 1 )
    notifies :restart, "service[carbon-cache]", :delayed
    notifies :restart, "service[carbon-relay]", :delayed
end

template "/opt/graphite/conf/storage-schemas.conf" do
    source "carbon-storage-schemas.conf.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[carbon-cache]", :delayed
end

template "/opt/graphite/conf/storage-aggregation.conf" do
    source "carbon-storage-aggregation.conf.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[carbon-cache]", :delayed
end

template "/opt/graphite/conf/relay-rules.conf" do
    source "carbon-relay-rules.conf.erb"
    owner "root"
    group "root"
    mode 00644
    variables( :servers => get_head_nodes )
    notifies :restart, "service[carbon-relay]", :delayed
end

service "apache2" do
    action [ :enable, :start ]
end

template "/etc/apache2/conf.d/graphite-web.conf" do
    source "apache-graphite-web.conf.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[apache2]", :delayed
end

%w{wsgi python}.each do |mod|
    bash "apache-enable-#{mod}" do
        user "root"
        code <<-EOH
            a2enmod #{mod}
        EOH
        not_if "test -r /etc/apache2/mods-enabled/#{mod}.load"
        notifies :restart, "service[apache2]", :delayed
    end
end

template "/opt/graphite/conf/graphite.wsgi" do
    source "graphite.wsgi.erb"
    owner "root"
    group "root"
    mode 00755
end

template "/opt/graphite/webapp/graphite/local_settings.py" do
    source "graphite.local_settings.py.erb"
    owner "root"
    group "root"
    mode 00644
    variables( :servers => get_head_nodes )
    notifies :restart, "service[apache2]", :delayed
end

execute "graphite-storage-ownership" do
    user "root"
    command <<-EOH
        chown -R www-data:www-data /opt/graphite/storage
    EOH
    not_if "ls -ald /opt/graphite/storage | awk '{print $3}' | grep www-data"
end

ruby_block "graphite-database-creation" do
    block do
        if not system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = \"#{node['bcpc']['graphite_dbname']}\"'|grep \"#{node['bcpc']['graphite_dbname']}\"" then
            %x[ mysql -uroot -p#{get_config('mysql-root-password')} -e "CREATE DATABASE #{node['bcpc']['graphite_dbname']};"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['graphite_dbname']}.* TO '#{get_config('mysql-graphite-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-graphite-password')}';"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['graphite_dbname']}.* TO '#{get_config('mysql-graphite-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-graphite-password')}';"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "FLUSH PRIVILEGES;"
            ]
            self.notifies :run, "bash[graphite-database-sync]", :immediately
            self.resolve_notification_references
        end
    end
end

bash "graphite-database-sync" do
    action :nothing
    user "root"
    code <<-EOH
        python /opt/graphite/webapp/graphite/manage.py syncdb --noinput
        python /opt/graphite/webapp/graphite/manage.py createsuperuser --username=admin --email=#{node[:bcpc][:admin_email]} --noinput
    EOH
    notifies :restart, "service[apache2]", :immediately
end

%w{carbon-cache carbon-relay}.each do |pkg|
    template "/etc/init.d/#{pkg}" do
        source "init.d-#{pkg}.erb"
        owner "root"
        group "root"
        mode 00755
        notifies :restart, "service[#{pkg}]", :delayed
    end
    service pkg do
        supports :restart => false
        action [ :enable, :start ]
    end
end

#
# Cookbook Name:: bcpc
# Recipe:: keystone
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

ruby_block "initialize-keystone-config" do
    block do
        make_config('mysql-keystone-user', "keystone")
        make_config('mysql-keystone-password', secure_password)
        make_config('keystone-admin-token', secure_password)
        make_config('keystone-admin-user', "admin")
        make_config('keystone-admin-password', secure_password)
    end
end

package "keystone" do
    action :upgrade
end

template "/etc/keystone/keystone.conf" do
    source "keystone.conf.erb"
    owner "keystone"
    group "keystone"
    mode 00600
    notifies :restart, "service[keystone]", :delayed
end

template "/root/adminrc" do
    source "adminrc.erb"
    owner "root"
    group "root"
    mode 00600
end

template "/root/keystonerc" do
    source "keystonerc.erb"
    owner "root"
    group "root"
    mode 00600
end

service "keystone" do
    action [ :enable, :start ]
end

ruby_block "keystone-database-creation" do
    block do
        if not system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = \"#{node['bcpc']['keystone_dbname']}\"'|grep \"#{node['bcpc']['keystone_dbname']}\"" then
            %x[ mysql -uroot -p#{get_config('mysql-root-password')} -e "CREATE DATABASE #{node['bcpc']['keystone_dbname']};"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['keystone_dbname']}.* TO '#{get_config('mysql-keystone-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-keystone-password')}';"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['keystone_dbname']}.* TO '#{get_config('mysql-keystone-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-keystone-password')}';"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "FLUSH PRIVILEGES;"
            ]
            self.notifies :run, "bash[keystone-database-sync]", :immediately
            self.resolve_notification_references
        end
    end
end

bash "keystone-database-sync" do
    action :run
    user "root"
    code "keystone-manage db_sync"
    notifies :restart, "service[keystone]", :immediately
end

bash "keystone-service-catalog-keystone" do
    user "root"
    code <<-EOH
        sleep 5
        . /root/keystonerc
        export KEYSTONE_ID=`keystone service-create --name=keystone --type=identity --description="Identity Service" | grep " id " | awk '{print $4}'`
        keystone endpoint-create --region #{node[:bcpc][:region_name]} --service_id $KEYSTONE_ID \
            --publicurl   "http://#{node[:bcpc][:management][:vip]}:5000/v2.0" \
            --adminurl    "http://#{node[:bcpc][:management][:vip]}:35357/v2.0" \
            --internalurl "http://#{node[:bcpc][:management][:vip]}:5000/v2.0"
    EOH
    not_if ". /root/keystonerc; keystone service-list | grep ' keystone '"
end

bash "keystone-service-catalog-glance" do
    user "root"
    code <<-EOH
        . /root/keystonerc
        export GLANCE_ID=`keystone service-create --name=glance --type=image --description="Image Service" | grep " id " | awk '{print $4}'`
        keystone endpoint-create --region #{node[:bcpc][:region_name]} --service_id $GLANCE_ID \
            --publicurl   "http://#{node[:bcpc][:management][:vip]}:9292/v1" \
            --adminurl    "http://#{node[:bcpc][:management][:vip]}:9292/v1" \
            --internalurl "http://#{node[:bcpc][:management][:vip]}:9292/v1"
    EOH
    not_if ". /root/keystonerc; keystone service-list | grep ' glance '"
end

bash "keystone-service-catalog-nova" do
    user "root"
    code <<-EOH
        . /root/keystonerc
        export NOVA_ID=`keystone service-create --name=nova --type=compute --description="Compute Service" | grep " id " | awk '{print $4}'`
        keystone endpoint-create --region #{node[:bcpc][:region_name]} --service_id $NOVA_ID \
            --publicurl   "http://#{node[:bcpc][:management][:vip]}:8774/v1.1/\\\$(tenant_id)s" \
            --adminurl    "http://#{node[:bcpc][:management][:vip]}:8774/v1.1/\\\$(tenant_id)s" \
            --internalurl "http://#{node[:bcpc][:management][:vip]}:8774/v1.1/\\\$(tenant_id)s"
    EOH
    not_if ". /root/keystonerc; keystone service-list | grep ' nova '"
end

bash "keystone-service-catalog-cinder" do
    user "root"
    code <<-EOH
        . /root/keystonerc
        export CINDER_ID=`keystone service-create --name=cinder --type=volume --description="Volume Service" | grep " id " | awk '{print $4}'`
        keystone endpoint-create --region #{node[:bcpc][:region_name]} --service_id $CINDER_ID \
            --publicurl   "http://#{node[:bcpc][:management][:vip]}:8776/v1/\\\$(tenant_id)s" \
            --adminurl    "http://#{node[:bcpc][:management][:vip]}:8776/v1/\\\$(tenant_id)s" \
            --internalurl "http://#{node[:bcpc][:management][:vip]}:8776/v1/\\\$(tenant_id)s"
    EOH
    not_if ". /root/keystonerc; keystone service-list | grep ' cinder '"
end

bash "keystone-service-catalog-ec2" do
    user "root"
    code <<-EOH
        . /root/keystonerc
        export EC2_ID=`keystone service-create --name=ec2 --type=ec2 --description="EC2 Service" | grep " id " | awk '{print $4}'`
        keystone endpoint-create --region #{node[:bcpc][:region_name]} --service_id $EC2_ID \
            --publicurl   "http://#{node[:bcpc][:management][:vip]}:8773/services/Cloud" \
            --adminurl    "http://#{node[:bcpc][:management][:vip]}:8773/services/Admin" \
            --internalurl "http://#{node[:bcpc][:management][:vip]}:8773/services/Cloud"
    EOH
    not_if ". /root/keystonerc; keystone service-list | grep ' ec2 '"
end

bash "keystone-service-catalog-s3" do
    action :nothing
    user "root"
    code <<-EOH
        . /root/keystonerc
        export S3_ID=`keystone service-create --name=s3 --type=s3 --description="S3 Service" | grep " id " | awk '{print $4}'`
        keystone endpoint-create --region #{node[:bcpc][:region_name]} --service_id $S3_ID \
            --publicurl   "http://#{node[:bcpc][:management][:vip]}:8080/" \
            --adminurl    "http://#{node[:bcpc][:management][:vip]}:8080/" \
            --internalurl "http://#{node[:bcpc][:management][:vip]}:8080/"
    EOH
    not_if ". /root/keystonerc; keystone service-list | grep ' s3 '"
end

bash "keystone-service-catalog-swift" do
    action :nothing
    user "root"
    code <<-EOH
        . /root/keystonerc
        export SWIFT_ID=`keystone service-create --name=swift --type=object-store --description="Swift Service" | grep " id " | awk '{print $4}'`
        keystone endpoint-create --region #{node[:bcpc][:region_name]} --service_id $SWIFT_ID \
            --publicurl   "http://#{node[:bcpc][:management][:vip]}:8080/v1/AUTH_\\\$(tenant_id)s" \
            --adminurl    "http://#{node[:bcpc][:management][:vip]}:8080/" \
            --internalurl "http://#{node[:bcpc][:management][:vip]}:8080/v1/AUTH_\\\$(tenant_id)s"
    EOH
    not_if ". /root/keystonerc; keystone service-list | grep ' swift '"
end

bash "keystone-service-catalog-quantum" do
#    action :nothing
    user "root"
    code <<-EOH
        . /root/keystonerc
        export QUANTUM_ID=`keystone service-create --name=quantum --type=network --description="Quantum Service" | grep " id " | awk '{print $4}'`
        keystone endpoint-create --region #{node[:bcpc][:region_name]} --service_id $QUANTUM_ID \
            --publicurl   "http://#{node[:bcpc][:management][:vip]}:9696/" \
            --adminurl    "http://#{node[:bcpc][:management][:vip]}:9696/" \
            --internalurl "http://#{node[:bcpc][:management][:vip]}:9696/"
    EOH
    not_if ". /root/keystonerc; keystone service-list | grep ' quantum '"
end

bash "keystone-create-users-tenants" do
    user "root"
    code <<-EOH
        . /root/adminrc
        . /root/keystonerc
        export KEYSTONE_ADMIN_TENANT_ID=`keystone tenant-create --name "#{node['bcpc']['admin_tenant']}" | grep " id " | awk '{print $4}'`
        export KEYSTONE_ROLE_ADMIN_ID=`keystone role-create --name "#{node['bcpc']['admin_role']}" | grep " id " | awk '{print $4}'`
        export KEYSTONE_ROLE_MEMBER_ID=`keystone role-create --name "#{node['bcpc']['member_role']}" | grep " id " | awk '{print $4}'`

        export KEYSTONE_ADMIN_LOGIN_ID=`keystone user-create --name "$OS_USERNAME" --tenant_id $KEYSTONE_ADMIN_TENANT_ID --pass "$OS_PASSWORD" --email "#{node['bcpc']['admin_email']}" --enabled true | grep " id " | awk '{print $4}'`

        for i in $KEYSTONE_ROLE_ADMIN_ID $KEYSTONE_ROLE_MEMBER_ID; do \
            keystone user-role-add --user_id $KEYSTONE_ADMIN_LOGIN_ID --role_id $i --tenant_id $KEYSTONE_ADMIN_TENANT_ID
        done

        # KEYSTONE_GLANCE_USER_ID=`keystone user-create --name $KEYSTONE_GLANCE_USER --tenant_id $KEYSTONE_SERVICE_TENANT_ID --pass $KEYSTONE_GLANCE_PASS --email $KEYSTONE_GLANCE_EMAIL --enabled true | grep " id " | awk '{print $4}'`
        # KEYSTONE_NOVA_USER_ID=`keystone user-create --name $KEYSTONE_NOVA_USER --tenant_id $KEYSTONE_SERVICE_TENANT_ID --pass $KEYSTONE_NOVA_PASS --email $KEYSTONE_NOVA_EMAIL --enabled true | grep " id " | awk '{print $4}'`
        # KEYSTONE_SWIFT_USER_ID=`keystone user-create --name $KEYSTONE_SWIFT_USER --tenant_id $KEYSTONE_SERVICE_TENANT_ID --pass $KEYSTONE_SWIFT_PASS --email $KEYSTONE_SWIFT_EMAIL --enabled true | grep " id " | awk '{print $4}'`
        # KEYSTONE_QUANTUM_USER_ID=`keystone user-create --name $KEYSTONE_QUANTUM_USER --tenant_id $KEYSTONE_SERVICE_TENANT_ID --pass $KEYSTONE_QUANTUM_PASS --email $KEYSTONE_QUANTUM_EMAIL --enabled true | grep " id " | awk '{print $4}'`

        # keystone user-role-add --user_id $KEYSTONE_ADMIN_USER_ID --role_id $KEYSTONE_ROLE_ADMIN_ID --tenant_id $KEYSTONE_SERVICE_TENANT_ID
        # keystone user-role-add --user_id $KEYSTONE_GLANCE_USER_ID --role_id $KEYSTONE_ROLE_ADMIN_ID --tenant_id $KEYSTONE_SERVICE_TENANT_ID
        # keystone user-role-add --user_id $KEYSTONE_NOVA_USER_ID --role_id $KEYSTONE_ROLE_ADMIN_ID --tenant_id $KEYSTONE_SERVICE_TENANT_ID
        # keystone user-role-add --user_id $KEYSTONE_SWIFT_USER_ID --role_id $KEYSTONE_ROLE_ADMIN_ID --tenant_id $KEYSTONE_SERVICE_TENANT_ID
        # keystone user-role-add --user_id $KEYSTONE_QUANTUM_USER_ID --role_id $KEYSTONE_ROLE_ADMIN_ID --tenant_id $KEYSTONE_SERVICE_TENANT_ID
    EOH
    not_if ". /root/keystonerc; . /root/adminrc; keystone user-list | grep $OS_USERNAME"
end

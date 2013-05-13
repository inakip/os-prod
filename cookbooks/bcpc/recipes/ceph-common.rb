#
# Cookbook Name:: bcpc
# Recipe:: ceph-common
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

include_recipe "bcpc::networking"

apt_repository "ceph" do
    uri node['bcpc']['repos']['ceph']
    distribution node['lsb']['codename']
    components ["main"]
    key "ceph-release.key"
end

%w{ceph python-ceph}.each do |pkg|
    package pkg do
        action :upgrade
    end
end

ruby_block "initialize-ceph-common-config" do
    block do
        make_config('ceph-fs-uuid', %x[uuidgen -r].strip)
        make_config('ceph-mon-key', %x[ceph-authtool /dev/null --name=mon. --gen-key -p].strip)
    end
end

ruby_block 'write-ceph-mon-key' do
    block do
        %x[ ceph-authtool "/etc/ceph/ceph.mon.keyring" \
                --create-keyring \
                --name=mon. \
                --add-key="#{get_config('ceph-mon-key')}" \
                --cap mon 'allow *'
        ]
    end
    not_if "test -f /etc/ceph/ceph.mon.keyring"
end

template '/etc/ceph/ceph.conf' do
    source 'ceph.conf.erb'
    mode '0644'
    variables( :servers => get_head_nodes )
end

Overview
========

This is a set of [Chef](https://github.com/opscode/chef) cookbooks to bring up
an instance of an [OpenStack](http://www.openstack.org/)-based cluster of head
and worker nodes.

Each head node runs all of the core services in a highly-available manner with
no restriction upon how many head nodes there are.  The cluster is deemed
operational as long as 50%+1 of the head nodes are online.  Otherwise, a
network partition may occur with a split-brain scenario.  In practice,
we currently recommend roughly one head node per rack.

Each worker node runs the relevant services (nova-compute, Ceph OSDs, etc.).
There is no limitation on the number of worker nodes.  In practice, we
currently recommend that the cluster should not grow to more than 200 worker
nodes.

Setup
=====

These recipes are currently intended for building a BCPC cloud on top of
Ubuntu 12.04 servers using Chef 10. When setting this up in VMs, be sure to
add a few dedicated disks (for ceph OSDs) aside from boot volume. In
addition, it's expected that you have three separate NICs per machine, with
the following as defaults (and recommendations for VM settings):
 - ``eth0`` - management traffic (host-only NIC in VM)
 - ``eth1`` - storage traffic (host-only NIC in VM)
 - ``eth2`` - VM traffic (host-only NIC in VM)
 - ``eth3`` - external gateway (NAT NIC in VM - only in bootstrap node)

You should look at the various settings in ``cookbooks/bcpc/attributes/default.rb``
and tweak accordingly for your setup (by adding them to an environment file).

Cluster Bootstrap
-----------------

Please refer to the [BCPC Bootstrap Guide](https://github.com/bloomberg/chef-bcpc/blob/master/bootstrap.md)
for more information about getting a BCPC cluster bootstrapped.

There are provided scripts which set up a Chef server that also permits imaging
of the cluster via PXE.

Once the Chef server is set up, you can bootstrap any number of nodes to get
them registered with the chef server for your environment - see the next
section for enrolling the nodes.

Make a cluster
--------------

To build a new cluster, you have to start with building a single
head node first. Since the recipes will automatically generate all passwords
and keys for this new cluster, enable the target node as an ``admin`` in the
chef server so that the recipes can write the generated info to a databag.
The databag will be called ``configs`` and the databag item will be the same
name as the environment (``Test-Laptop`` in this example). You only need to
leave the node as an ``admin`` for the first chef-client run. You can also
manually create the databag & item (as per the example in
``data_bags/configs/Example.json``) and manually upload it if you'd rather
not bother with the whole ``admin`` thing for the first run.

So add this first node as the role ``BCPC-Headnode`` and run ``chef-client``
on the target node. After the first one is up, you can add another head
node with:

```
 $ knife bootstrap -E Test-Laptop -r "role[BCPC-Headnode]" <IPAddress>
```

Or enroll a server as a worker node:

```
 $ knife bootstrap -E Test-Laptop -r "role[BCPC-Worknode]" <IPAddress>
```

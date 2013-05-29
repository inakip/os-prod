#!/bin/bash
knife cookbook upload -a -o cookbooks
sudo chmod 644 /etc/chef/{validation.pem,client.pem}
sudo knife bootstrap -E bcpc-vm -r 'role[BCPC-Bootstrap]' 192.168.122.138 -x ubuntu --sudo
sudo cobbler sync

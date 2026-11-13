#!/bin/sh
(cd preseed && packer build -force .)
vagrant destroy -f
vagrant box remove -f debian-lvm || true
vagrant up

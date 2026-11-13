# install ACL
sudo apt-get update -y
sudo apt-get install acl -y
# users
sudo useradd -m -s /bin/bash admin1
sudo useradd -m -s /bin/bash dev1
sudo useradd -m -s /bin/bash deploy1
# Passwords so `sudo` works. Lab-only default; a real deployment would inject
# these via Vagrant env (e.g. $ADMIN1_PW) or pull from a secrets manager.
echo -e 'admin1:changeme\ndev1:changeme\ndeploy1:changeme' | sudo chpasswd
# groups
sudo groupadd shared
sudo groupadd admin
sudo groupadd developer
sudo groupadd deploy

sudo usermod -aG admin,shared admin1
sudo usermod -aG developer,shared dev1
sudo usermod -aG deploy deploy1

sudo mkdir -p /srv/shared
sudo chown root:shared /srv/shared

sudo chmod 2770 /srv/shared

sudo setfacl -m g:deploy:r-x /srv/shared

sudo setfacl -d -m u::rwx,g::rwx,g:deploy:r-x,o::--- /srv/shared

sudo mkdir -p /srv/scratch

sudo chmod 1777 /srv/scratch

## sudoers abilities
# admin group
sudo tee /etc/sudoers.d/admin > /dev/null <<'EOF'
%admin ALL=(ALL:ALL) ALL
EOF

sudo tee /etc/sudoers.d/docker-clean > /dev/null <<'EOF'
Cmnd_Alias DOCKER_RESTART = /usr/bin/systemctl restart docker-clean

%developer ALL=(root) NOPASSWD: DOCKER_RESTART
%deploy    ALL=(root) NOPASSWD: DOCKER_RESTART
EOF

sudo chmod 0440 /etc/sudoers.d/admin /etc/sudoers.d/docker-clean
sudo visudo -c

## SSH key directory for admin1 (authorized_keys written per-host in Vagrantfile)
sudo install -d -m 0700 -o admin1 -g admin1 /home/admin1/.ssh
sudo install -m 0600 -o admin1 -g admin1 \
  /vagrant/remote_machines_ed25519.pub /home/admin1/.ssh/authorized_keys
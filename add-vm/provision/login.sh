# install ACL
sudo apt-get update -y
sudo apt-get install acl -y
# users
sudo useradd -m -s /bin/bash admin1
sudo useradd -m -s /bin/bash dev1
sudo useradd -m -s /bin/bash deploy1
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

## ssh
#ssh-copy-id $(whoami)@"$host"
#sudo tee /etc/ssh/sshd_config.d/00-keys-only.conf << 'EOF'
#PubKeyAuthentication yes
#PasswordAuthentication no
#KbdInteractiveAuthentication no
#PermitRootLogin no
#EOF

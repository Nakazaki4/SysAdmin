apt-get install -y -q sshguard

sed -i -e 's/^THRESHOLD=.*/THRESHOLD=50/' \
  -e 's/^BLOCK_TIME=.*/BLOCK_TIME=60/' \
  -e 's/^DETECTION_TIME=.*/DETECTION_TIME=300/' \
  /etc/sshguard/sshguard.conf

systemctl restart sshguard

# admin1 on the gateway holds the key used to reach the clients
# sudo install -m 0600 -o admin1 -g admin1 \
#   /vagrant/remote_machines_ed25519.pub /home/admin1/.ssh/authorized_keys

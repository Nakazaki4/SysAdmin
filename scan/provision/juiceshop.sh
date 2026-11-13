# Add Docker's official GPG key:
apt-get -y update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get -y update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
docker --version

docker pull bkimminich/juice-shop
# Bind to loopback only. The subnet-wide listener is nginx (see nginx.sh),
# which strips the sensitive paths before proxying to this container.
# Kill any prior juice-shop container (named or anonymous) so rerunning
# this script is safe.
docker ps -aq --filter ancestor=bkimminich/juice-shop | xargs -r docker rm -f
docker run -d --restart=unless-stopped --name juiceshop \
  -p 127.0.0.1:3000:3000 bkimminich/juice-shop
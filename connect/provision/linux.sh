#!/bin/bash
script_path=/usr/local/bin/docker-clean.sh
touch script_path
cat << 'EOF' > script_path
echo "= Disk usage before ="
docker system df
echo

docker container prune -f
docker network prune -f
docker builder prune -f

echo
echo "= Disk usage after ="
docker system df
EOF

sudo chmod +x script_path

touch /etc/systemd/system/docker-clean.service
cat << 'EOF' > /etc/systemd/system/docker-clean.service
[Unit]
Description=Clean unused docker resources
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/docker-clean.sh
Restart=always
RestartSec=5s
StandardOutput=journal
StandardError=journal
Environment=INTERVAL=3600
EOF


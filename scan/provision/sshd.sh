#!/bin/bash
set -euo pipefail

cat > /etc/ssh/sshd_config.d/00-hardening.conf <<EOF
PubKeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
LogLevel VERBOSE
EOF

sshd -t
systemctl reload ssh

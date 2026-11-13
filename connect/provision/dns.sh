cat > /etc/dnsmasq.d/dns.conf <<'EOF'
# DNS on both subnets
interface=enp0s8
interface=enp0s9
bind-interfaces
domain=lab.internal
local=/lab.internal/
no-hosts
host-record=gateway.lab.internal,gateway,10.10.10.10
host-record=clientA.lab.internal,clientA,10.10.10.20
host-record=clientB.lab.internal,clientB,10.10.20.20
dhcp-option=option:domain-search,lab.internal
log-queries
EOF

dnsmasq --test
systemctl restart dnsmasq

apt-get install -y -q dnsmasq

cat > /etc/dnsmasq.d/dhcp.conf <<'EOF'
interface=enp0s8
bind-interfaces
no-dhcp-interface=enp0s9
dhcp-range=10.10.10.100,10.10.10.199,255.255.255.0,6h
dhcp-host=00:1A:2B:3C:4D:5F,clientA,10.10.10.20,infinite

dhcp-authoritative
log-dhcp
EOF

dnsmasq --test
systemctl restart dnsmasq

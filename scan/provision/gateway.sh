#!/usr/bin/env bash
# gateway.sh - interfaces, routing, NAT and firewall on the gateway.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

WAN=enp0s3              # VirtualBox NAT -> internet
INTERFACE_A=enp0s8             # subnet A
INTERFACE_B=enp0s9             # subnet B
NETWORK_A=10.10.10.0/24
NETWORK_B=10.10.20.0/24       # client B: runs the one allowed service (HTTP)

## Interfaces: one address in each subnet
grep -q '^source /etc/network/interfaces.d' /etc/network/interfaces ||
  echo 'source /etc/network/interfaces.d/*' >> /etc/network/interfaces

cat > /etc/network/interfaces.d/lab <<EOF
auto $INTERFACE_A
iface $INTERFACE_A inet static
    address 10.10.10.10/24

auto $INTERFACE_B
iface $INTERFACE_B inet static
    address 10.10.20.10/24
EOF

# Bring up only these two; enp0s3 (vagrant ssh) is never touched
for i in $INTERFACE_A $INTERFACE_B; do
  ifdown --force "$i" 2>/dev/null || true
  ifup "$i"
done

## Routing: forward packets between interfaces (now and at every boot)
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ipforward.conf
sysctl -q --system

## Tools
apt-get update -q
apt-get install -y -q iptables iptables-persistent dnsutils tcpdump

## Firewall: start clean, so running this again doesn't duplicate rules
iptables -F FORWARD
iptables -t nat -F POSTROUTING
iptables -P FORWARD DROP                                    # default deny

# Replies to allowed traffic (echo-reply, HTTP responses, internet replies)
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Between the subnets: exactly two things
# 1. ICMP, both directions
iptables -A FORWARD -s $NETWORK_A -d $NETWORK_B -p icmp -m comment --comment "allow: icmp A->B" -j ACCEPT
iptables -A FORWARD -s $NETWORK_B -d $NETWORK_A -p icmp -m comment --comment "allow: icmp B->A" -j ACCEPT
iptables -A FORWARD -s $NETWORK_A -d $NETWORK_B -p tcp --dport 3000 -j ACCEPT

# Both subnets -> internet (only out through the WAN, so it can't open A<->B)
iptables -A FORWARD -s $NETWORK_A -o $WAN -j ACCEPT
iptables -A FORWARD -s $NETWORK_B -o $WAN -j ACCEPT

# Log a sample of what the policy drops (journalctl -k | grep fw-drop)
iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "fw-drop: "

## NAT: leave the gateway with its WAN address
iptables -t nat -A POSTROUTING -s $NETWORK_A -o $WAN -j MASQUERADE
iptables -t nat -A POSTROUTING -s $NETWORK_B -o $WAN -j MASQUERADE

# sudo iptables -t nat -A PREROUTING -i enp0s3 -p tcp --dport 3000 -j DNAT --to-destination 10.10.20.20:3000
# sudo iptables -A FORWARD -p tcp -d 10.10.20.20 --dport 3000 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
# sudo iptables -t nat -A POSTROUTING -p tcp -d 10.10.20.20 --dport 3000 -j MASQUERADE

## Keep the rules after a reboot (/etc/iptables/rules.v4)
netfilter-persistent save
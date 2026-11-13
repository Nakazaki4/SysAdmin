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
iptables -F INPUT
iptables -t nat -F POSTROUTING
iptables -P FORWARD DROP                                    # default deny on transit
iptables -P INPUT DROP                                      # default deny on the gateway itself

# Replies to allowed traffic (echo-reply, HTTP responses, internet replies)
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT   -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT   -i lo -j ACCEPT

# INPUT (traffic TO the gateway itself): finding F4 — SSH and DNS were exposed
# on the subnet-B interface. The vagrant NAT adapter (enp0s3) must stay fully
# open so provisioning and `vagrant ssh` keep working.
iptables -A INPUT -i $WAN -j ACCEPT
# DHCP server on the subnet-A interface (dnsmasq hands out leases to clientA).
# The request comes from 0.0.0.0 to 255.255.255.255, so match by interface.
iptables -A INPUT -i $INTERFACE_A -p udp --dport 67 -m comment --comment "F4: allow DHCP A->gw" -j ACCEPT
# DNS from both lab subnets (the gateway is their resolver, see dns.sh)
iptables -A INPUT -s $NETWORK_A -p udp --dport 53 -m comment --comment "F4: allow DNS A->gw" -j ACCEPT
iptables -A INPUT -s $NETWORK_B -p udp --dport 53 -m comment --comment "F4: allow DNS B->gw" -j ACCEPT
iptables -A INPUT -s $NETWORK_A -p tcp --dport 53 -m comment --comment "F4: allow DNS-TCP A->gw" -j ACCEPT
iptables -A INPUT -s $NETWORK_B -p tcp --dport 53 -m comment --comment "F4: allow DNS-TCP B->gw" -j ACCEPT
# ICMP so ping and path discovery keep working
iptables -A INPUT -p icmp -j ACCEPT
# Everything else to the gateway (including SSH/22 from the lab) is dropped by policy.

# Between the subnets: ICMP in both directions, and the one allowed service.
iptables -A FORWARD -s $NETWORK_A -d $NETWORK_B -p icmp -m comment --comment "allow: icmp A->B" -j ACCEPT
iptables -A FORWARD -s $NETWORK_B -d $NETWORK_A -p icmp -m comment --comment "allow: icmp B->A" -j ACCEPT

# F2 remediation — rate-limit the Juice Shop port on NEW connections to blunt
# brute-force. 10 new connections per source IP per minute is enough for an
# admin browsing the app, far too few for a credential-stuffing run.
iptables -A FORWARD -s $NETWORK_A -d $NETWORK_B -p tcp --dport 3000 \
  -m conntrack --ctstate NEW \
  -m hashlimit --hashlimit-above 10/minute --hashlimit-burst 20 \
  --hashlimit-mode srcip --hashlimit-name juiceshop \
  -m comment --comment "F2: rate-limit NEW conns to juiceshop" -j DROP
iptables -A FORWARD -s $NETWORK_A -d $NETWORK_B -p tcp --dport 3000 \
  -m comment --comment "allow: juiceshop A->B" -j ACCEPT

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
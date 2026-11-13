# Scan methodology (before-remediation baseline)

All scans in this directory were run from **clientA** (`10.10.10.20`, subnet A).
That is the vantage point an outsider who has pivoted onto subnet A would have:
no credentials on clientB, no shell on the gateway, only L2 access to subnet A
and L3 reachability to subnet B through the gateway's firewall.

Each scan is saved to its own file. File names are prefixed with the step number
in the methodology so they sort in the order they were run.

## What I looked for, in what order, and why

### Step 1 — Link layer discovery (`arp-scan`)

Goal: find every host on the local L2 segment, including any that refuses to
answer higher-layer probes.

- `arp-scan --localnet` on `enp0s8` (the subnet-A interface). ARP replies cannot
  be suppressed by host firewalls because they happen below IP, so this is the
  most reliable sweep for hosts that share a broadcast domain.
- Running it a second time against the subnet-B range (`10.10.20.0/24`). I do
  **not** expect this to discover hosts on subnet B — ARP does not cross a
  router — but the replies tell me whether the gateway proxy-ARPs on behalf of
  subnet B, which is itself an information disclosure.

### Step 2 — Network-layer discovery (`nmap -sn`)

Goal: find hosts in subnet B that are reachable at L3 through the gateway.

- `nmap -sn -PE 10.10.20.0/24` from clientA. `-PE` forces ICMP echo so the
  probe does not rely on open TCP ports that may be filtered. ICMP is allowed
  A↔B by the gateway firewall, so any live host in subnet B should answer.

### Step 3 — Port enumeration (full TCP SYN sweep)

Goal: find every TCP port exposed by every discovered host to subnet A.

- `nmap -Pn -sS -p- -T4 --min-rate 2000 --open <host>` per host. `-p-` covers all
  65535 ports, `-sS` uses a SYN scan (requires root, faster and quieter than a
  full connect), `-Pn` skips host discovery (we already did that in step 2),
  `--min-rate` keeps the scan from stalling on filtered ports.
- The subject warned that this takes tens of minutes. Each run is saved; nothing
  is re-run unless the inputs change.

### Step 4 — Service and version detection (`-sV`)

Goal: for every open port found in step 3, identify the service and version.

- `nmap -sV -p <ports> <host>` scoped to the ports step 3 found open. Running
  `-sV` against all 65535 ports is wasteful.
- Version strings feed CVE lookups and tell me which attacks are plausible
  before I ever send a payload.

### Step 5 — Default-script scan (`-sC`)

Goal: let nmap's NSE default scripts pull more context from each open service
(HTTP titles, headers, banner, SMB shares, SSH key types, etc.) — a cheap way
to surface misconfigurations without writing any code.

- `nmap -sC -p <ports> <host>`.

### Step 6 — OS fingerprinting (`-O`)

Goal: identify the operating system where possible.

- `nmap -O <host>`. Needs root. Works best when there is a mix of open and
  closed TCP ports; in a locked-down environment OS detection often returns
  "Too many fingerprints match" or no match.

### Step 7 — Application-layer probes

Goal: walk the HTTP service like a user would, then check a few well-known
information-disclosure paths. Not a scanner; done with `curl`. Saved as
separate files per endpoint.

- `GET /` — baseline
- `GET /rest/admin/application-version` — Juice Shop's version endpoint
- `GET /ftp` — Juice Shop's documented directory-listing exposure
- `POST /rest/user/login` — tested with a SQL-injection payload and with a
  rapid burst of wrong passwords to check for rate-limiting

## Why this order

Each step is cheap compared to the one after it, and each narrows the target
for the next. ARP tells me who is there. `nmap -sn` extends that across the
router. `-p-` tells me what is open. `-sV`/`-sC` tell me what it is. `-O` tells
me what OS it runs on. Only then do I send application-layer payloads.

Reversing this order would waste time (running `-sV --script=http-*` against
all 65535 ports instead of the one that was open) and send more noise than
necessary — which, in a real engagement, is how you get caught.

## Evidence files

| File | Scan |
|---|---|
| `01-arp-scan-subnetA.txt` | arp-scan local L2 sweep |
| `02-arp-scan-subnetB-range.txt` | arp-scan against subnet B range (proxy-ARP check) |
| `03-nmap-sn-subnetB.txt` | nmap L3 host discovery, subnet B |
| `04-nmap-full-tcp-clientB.txt` | nmap -p- SYN sweep, clientB |
| `05-nmap-full-tcp-gateway.txt` | nmap -p- SYN sweep, gateway (subnet-B side) |
| `06-nmap-sV-sC-clientB.txt` | service, version, default scripts on open ports |
| `07-nmap-O-clientB.txt` | OS fingerprint |
| `08-curl-version.txt` | Juice Shop version endpoint |
| `09-curl-ftp.txt` | /ftp directory listing |
| `10-curl-sqli-login.txt` | SQLi payload on /rest/user/login + decoded JWT |
| `11-curl-ratelimit.txt` | burst of wrong passwords for rate-limit check |

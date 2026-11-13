# Remediation notes

Each finding is linked to the commit that fixes it. All fixes live in the IaC
(`provision/*.sh`, `Vagrantfile`) so they survive a `vagrant destroy && up`.

| Finding | Status | Commit | File |
|---|---|---|---|
| F2 — No login rate-limit | Fixed via network containment | `c131905` | `provision/gateway.sh` |
| F3 — Info disclosure (`/rest/admin/application-version`, `/ftp`) | Fixed via reverse proxy on clientB | `29a641c` | `provision/juiceshop.sh`, `provision/nginx.sh`, `Vagrantfile` |
| F4 — Gateway exposed SSH/DNS on subnet-B interface | Fixed | `c131905` + `6bcb042` | `provision/gateway.sh` |
| Extra — `admin1`/`dev1`/`deploy1` had no password | Fixed | `a81a167` | `provision/login.sh` |

## What each commit changes

### `c131905` — gateway firewall: INPUT chain + rate-limit

File: [provision/gateway.sh](../provision/gateway.sh)

- Introduced an INPUT chain with default DROP on the gateway. Previously only
  the FORWARD chain was filtered, so traffic *terminating on the gateway* (SSH,
  DNS) was reachable from both lab subnets. Now:
  - Vagrant NAT (`enp0s3`) stays fully open so provisioning keeps working.
  - UDP/53 is allowed from both lab subnets (the gateway is their resolver).
  - ICMP to the gateway is allowed for ping and path discovery.
  - Everything else — including SSH/22 — is dropped by policy.
- Added a hashlimit rule in front of the A→B:3000 ACCEPT. New connections from
  any one source IP are capped at 10/min with a burst of 20. A human browsing
  Juice Shop is unaffected; a brute-force loop is DROPped after the burst.

### `6bcb042` — gateway firewall: F4 follow-up

File: [provision/gateway.sh](../provision/gateway.sh)

- The initial F4 remediation blocked DHCP alongside SSH, breaking clientA's
  address assignment on a fresh rebuild. Added explicit INPUT accepts for
  UDP/67 on the subnet-A interface and TCP/53 from both subnets.

### `29a641c` — containment of Juice Shop's information disclosure

Files: [provision/juiceshop.sh](../provision/juiceshop.sh),
[provision/nginx.sh](../provision/nginx.sh), [Vagrantfile](../Vagrantfile).

- Juice Shop is now started with `-p 127.0.0.1:3000:3000` instead of
  `-p 0.0.0.0:3000:3000`, so the container is only reachable from inside
  clientB.
- A new provisioner `nginx.sh` installs nginx and configures it as the
  subnet-facing listener on `10.10.20.20:3000`. Two `location` blocks
  return 404 before the request reaches the upstream:
  - `^/ftp(/|$)` — the training-content directory listing.
  - `/rest/admin/application-version` — the unauthenticated version banner.
- All other paths proxy through to `http://127.0.0.1:3000` unchanged, so the
  app continues to function — containment at the perimeter, not a service patch.
- `nginx.sh` is wired into clientB **after** the network inline, because
  nginx binds to the lab IP and that address is not up until the inline
  `ifup enp0s8` runs.
- Also fixes a pre-existing typo `apt-get incertistall` in `juiceshop.sh`
  that would have broken fresh provisioning.

### `a81a167` — login.sh: set passwords for the three lab users

File: [provision/login.sh](../provision/login.sh)

- `admin1`, `dev1`, `deploy1` were created with `useradd -m` and no password,
  meaning `sudo` prompts were unanswerable. Set a lab-only default password of
  `changeme`. A real deployment should inject the password through a Vagrant
  env var or a secrets manager (SOPS, ansible-vault, etc.).

## Accepted risks (documented, not fixed)

| Issue | Reason for acceptance |
|---|---|
| `remote_machines_ed25519` private key lives in the repo and is mounted into the gateway at `/vagrant/remote_machines_ed25519` | Lab convenience. The whole-lab topology assumes anyone with repo access is already a trusted user. A real deployment would generate the key on first provision and never check it in. |
| `AllowUsers *@10.0.2.*` on clientB | Required so `vagrant provision clientB` works through the NAT adapter. Removing it makes future rebuilds fail. In a real environment there would be no NAT adapter and no need for this clause. |

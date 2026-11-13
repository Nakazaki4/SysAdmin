# Remediation notes

Each finding is linked to the commit that fixes it. All fixes live in the IaC
(`provision/*.sh`, `Vagrantfile`) so they survive a `vagrant destroy && up`.

| Finding | Status | Commit | File |
|---|---|---|---|
| F1 — SQLi admin bypass on `/rest/user/login` | Compensating controls only (service cannot be patched) | see F2, F4 | `provision/gateway.sh` |
| F2 — No login rate-limit | Fixed via network containment | `c131905` | `provision/gateway.sh` |
| F3 — Info disclosure (`/rest/admin/application-version`, `/ftp`) | Accepted risk + segmentation | existing segmentation in `provision/gateway.sh` | `provision/gateway.sh` |
| F4 — Gateway exposed SSH/DNS on subnet-B interface | Fixed | `c131905` | `provision/gateway.sh` |
| F5 — Weak admin password + MD5-in-JWT | Compensating controls only | see F2 | `provision/gateway.sh` |
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
  This is the containment remediation for F2, and is the closest the network
  layer can get to mitigating F1/F5 (it raises the cost of SQLi retries and of
  stealing a token, though a single successful SQLi still works).

### `a81a167` — login.sh: set passwords for the three lab users

File: [provision/login.sh](../provision/login.sh)

- `admin1`, `dev1`, `deploy1` were created with `useradd -m` and no password,
  meaning `sudo` prompts were unanswerable. Set a lab-only default password of
  `changeme`. A real deployment should inject the password through a Vagrant
  env var or a secrets manager (SOPS, ansible-vault, etc.).

## Why some findings are not "fixed" in the traditional sense

The subject explicitly asks: for the deliberately vulnerable service, patch by
**containment** rather than by modifying the application.

- **F1 (SQLi admin bypass)** and **F5 (weak password + MD5 hash in JWT)** are
  Juice Shop bugs. The application is intentionally vulnerable and ships
  pre-seeded with these flaws. The containment is:
  - Juice Shop is reachable only from subnet A, not from the internet or the
    NAT host (host port forward disabled in Vagrantfile).
  - Rate-limit (F2 fix) makes credential-stuffing slow and makes repeated SQLi
    attempts from one source noisy and self-limiting.
  - No further IaC change; documented as accepted risk.

- **F3 (info disclosure)** cannot be fixed at the firewall level because `/ftp`
  and `/rest/admin/application-version` are served on the same port as the
  rest of the app. A reverse proxy on clientB with a path allowlist would be
  the next level of containment; that is a larger change and was declined for
  this project's scope. The accepted mitigation is:
  - The port is only reachable from subnet A (segmentation).
  - Juice Shop's `/ftp` directory contains files intentionally planted for
    training (`incident-support.kdbx`, `coupons_2013.md.bak`, etc.); nothing
    in that directory is production data.
  - Documented in the report under "accepted risk".

## Accepted risks (documented, not fixed)

| Issue | Reason for acceptance |
|---|---|
| `remote_machines_ed25519` private key lives in the repo and is mounted into the gateway at `/vagrant/remote_machines_ed25519` | Lab convenience. The whole-lab topology assumes anyone with repo access is already a trusted user. A real deployment would generate the key on first provision and never check it in. |
| `AllowUsers *@10.0.2.*` on clientB | Required so `vagrant provision clientB` works through the NAT adapter. Removing it makes future rebuilds fail. In a real environment there would be no NAT adapter and no need for this clause. |
| Juice Shop internal vulnerabilities (F1, F3, F5) | The service is deliberately vulnerable and must still deploy on rebuild (subject requirement). |

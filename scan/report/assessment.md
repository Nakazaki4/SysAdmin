# Security assessment — lab network with Juice Shop

**Assessor:** Nakazaki
**Date:** 2026-11-13
**Scope:** The three-VM lab defined by `Vagrantfile` — one gateway bridging two
isolated subnets (A: `10.10.10.0/24`, B: `10.10.20.0/24`), one DHCP client on
subnet A (`clientA`), one web-service host on subnet B (`clientB`) running
OWASP Juice Shop 20.4.0-SNAPSHOT behind the gateway.
**Vantage point:** an outsider with L2 access to subnet A and no credentials —
i.e. a shell on `clientA`, nothing else.

---

## 1. Executive summary

The lab's network segmentation was mostly correct going in, but the firewall
was only enforcing the *transit* path. The gateway itself was reachable on
SSH from inside the lab — a textbook unintended foothold. The Juice Shop
service, by design, ships with multiple application-level vulnerabilities; the
only question was how well the environment around it *contained* those bugs.
It turned out it did not contain them at all: there was no rate-limit between
subnet A and the service, so the one SQL-injection bug that unlocks the admin
account could be chained with unlimited password guessing.

Five findings were investigated. Three of them (F2, F3, F4) were closed by
changes to the Infrastructure-as-Code so that rebuilding the lab from scratch
does not reintroduce them — including F3, which was contained by adding an
nginx reverse-proxy on clientB that strips the two information-disclosure
paths before they reach Juice Shop. The remaining two (F1, F5) are Juice
Shop internals which the project rules forbid patching; those are documented
as accepted risk with the compensating controls (rate-limit, segmentation)
that mitigate them.

| ID | Finding | Severity | Likelihood | Status |
|---|---|---|---|---|
| F1 | SQL injection admin bypass on `/rest/user/login` | Critical | High | Compensating controls (containment) |
| F2 | No rate-limit on the authentication endpoint | High | High | **Fixed** (gateway hashlimit) |
| F3 | Information disclosure (`/rest/admin/application-version`, `/ftp`) | Medium | High | **Fixed** (nginx reverse proxy strips the paths) |
| F4 | Gateway exposed SSH and DNS to the lab subnets | High | Medium | **Fixed** (gateway INPUT chain) |
| F5 | Weak admin password + MD5 hash leaked in JWT | High | Medium | Compensating controls (rate-limit) |

An additional configuration defect — three local users created without a
password, making `sudo` unusable — was found during exploitation and fixed
in the same pass.

---

## 2. Methodology

Full methodology document: [scans/before/00-methodology.md](../scans/before/00-methodology.md).

In short, I worked from the outside in, following the layering of the
protocols involved:

1. **ARP** — `arp-scan --localnet` on clientA's subnet-A interface, then on
   the subnet-B range to confirm ARP does not cross the router.
2. **IP** — `nmap -sn -PE` across subnet B, using ICMP since the gateway
   permits ICMP both ways.
3. **TCP** — `nmap -Pn -sS -p-` full-port SYN sweep of every discovered host
   (clientB and the gateway's subnet-B interface).
4. **Service + version + default scripts** — `nmap -sV -sC` against only the
   ports that step 3 reported as open, to save time.
5. **OS fingerprint** — `nmap -O` best-effort; works poorly against highly
   filtered hosts, as expected.
6. **HTTP application-layer probes** — `curl` against known Juice Shop
   endpoints, plus a SQL-injection payload on login and a burst of wrong
   passwords for rate-limit testing.

All scans were run from `clientA` via a bastion (gateway) SSH hop. Every
scan was saved to `scans/before/NN-name.txt` before being read, and re-run
without modification into `scans/after/` after remediation. See the
methodology doc for the exact ordering and justification.

---

## 3. Findings

### F1 — SQL injection admin takeover on `POST /rest/user/login`

**Severity:** Critical  —  **Likelihood:** High (the endpoint is reachable
unauthenticated; a single request lands the exploit)

**What it is.** Juice Shop's login endpoint concatenates the `email` request
body field directly into its SQL query. A classic single-quote tautology
(`' OR 1=1--`) matches every row, the server returns the first — which
happens to be the administrator — and issues a signed JWT for that account.

**Evidence.** [scans/before/10-curl-sqli-login.txt](../scans/before/10-curl-sqli-login.txt)
shows the server returning HTTP 200 with a token in the `authentication.token`
field. Decoded JWT payload:

```json
{
  "data": {
    "id": 1,
    "email": "admin@juice-sh.op",
    "password": "0192023a7bbd73250516f069df18b500",
    "role": "admin"
  }
}
```

**Reproduction (from clientA).**

```bash
curl -s -X POST http://10.10.20.20:3000/rest/user/login \
  -H 'Content-Type: application/json' \
  --data-raw "{\"email\":\"' OR 1=1--\",\"password\":\"x\"}"
```

**Demonstrated impact.** Full administrative access to the Juice Shop user
database, order history, product catalogue, and administrative APIs through
the returned JWT. Combined with F5, the admin's password hash is also
disclosed in the same response and is trivially crackable offline.

**Remediation.** Juice Shop is intentionally vulnerable and cannot be patched
(project constraint). Containment:

- The service is only reachable from subnet A, which in a real environment
  would be a restricted admin VLAN. The Vagrantfile disables the host port
  forward for clientB so there is no bypass from the host.
- The rate-limit added for F2 raises the cost of iterating payloads from one
  source, though it does not prevent the one-shot exploit.

**Verification command (fails for this finding — exploit still works).**

```bash
curl -s -X POST http://10.10.20.20:3000/rest/user/login \
  -H 'Content-Type: application/json' \
  --data-raw "{\"email\":\"' OR 1=1--\",\"password\":\"x\"}" | grep -q token && echo "F1 OPEN (expected, accepted)"
```

---

### F2 — No rate-limit on the authentication endpoint

**Severity:** High  —  **Likelihood:** High

**What it is.** The Juice Shop login endpoint has no backoff, no lockout, and
no CAPTCHA. Ten failed logins in roughly a tenth of a second get ten normal
HTTP 401 responses. A credential-stuffing attack against the whole user table
runs at line rate until the attacker finds a match.

**Evidence.** [scans/before/11-curl-ratelimit.txt](../scans/before/11-curl-ratelimit.txt):
10 failed attempts in ~0.1 s wall time, every response returned at full speed.

**Reproduction.**

```bash
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "attempt=%{http_code} time=%{time_total}s\n" \
    -X POST http://10.10.20.20:3000/rest/user/login \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"admin@juice-sh.op\",\"password\":\"wrong$i\"}"
done
```

**Demonstrated impact.** On its own: no secret is recovered, but the primitive
exists. Combined with F5 (admin password is `admin123`) it means an attacker
without the SQLi (F1) can still brute-force the admin account in seconds using
a trivial wordlist.

**Remediation.** Commit [`c131905`](../remediation/notes.md). Added an
iptables `hashlimit` rule on the gateway that drops NEW TCP connections to
clientB:3000 after a burst of 20 and more than 10/minute per source IP. A
human using the app is unaffected; a brute-force loop is DROPped. This is a
network-layer containment because the project forbids patching Juice Shop.

**Verification command (passes after remediation).**

```bash
# Expect several attempt=000 (connection dropped / timed out) within 25 attempts
for i in $(seq 1 25); do
  curl -s --max-time 5 -o /dev/null -w "%{http_code}\n" \
    -X POST http://10.10.20.20:3000/rest/user/login \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"a@b\",\"password\":\"x$i\"}"
done | grep -c '^000'
# Non-zero count = rate-limit is active
```

**Before vs after.**

| File | Content |
|---|---|
| `scans/before/11-curl-ratelimit.txt` | All 10 attempts served in ~0.01 s, status 401. |
| `scans/after/11-curl-ratelimit.txt` | Several attempts return `status=000 time=5.00s` (dropped by hashlimit) after the burst is exhausted. |

---

### F3 — Information disclosure (`/rest/admin/application-version`, `/ftp`)

**Severity:** Medium  —  **Likelihood:** High

**What it is.** Two unauthenticated endpoints leak sensitive information:

- `GET /rest/admin/application-version` returns the exact Juice Shop version,
  enabling direct CVE lookup. Despite the `/admin/` path prefix, no
  authentication is required.
- `GET /ftp` serves an HTML directory listing of a server-side folder, which
  contains `incident-support.kdbx` (a KeePass database), `coupons_2013.md.bak`
  (business data), `package.json.bak`, `legal.md`, and more.

**Evidence.**
- [scans/before/08-curl-version.txt](../scans/before/08-curl-version.txt) →
  `{"version":"20.4.0-SNAPSHOT"}`
- [scans/before/09-curl-ftp.txt](../scans/before/09-curl-ftp.txt) → full HTML
  directory listing with 11 named files.

**Reproduction.**

```bash
curl -s http://10.10.20.20:3000/rest/admin/application-version
curl -s http://10.10.20.20:3000/ftp
```

**Demonstrated impact.** Version pivot (CVE lookup) and direct download of
encrypted secrets (`incident-support.kdbx`), coupon codes, and the app's
`package.json.bak` which reveals the full dependency tree.

**Remediation.** Commit [`29a641c`](../remediation/notes.md). Juice
Shop is now bound to `127.0.0.1:3000` inside clientB, and nginx listens on
`10.10.20.20:3000` as a reverse proxy. Two `location` blocks return 404 for
the sensitive paths before the request ever reaches the app:

```nginx
location ~ ^/ftp(/|$)                         { return 404; }
location = /rest/admin/application-version    { return 404; }
```

Everything else is proxied through unchanged, so the app still functions and
the SQLi (F1) still demonstrates — containment at the perimeter, not a patch
to the service. This matches the subject's "firewall policy, network
segmentation, access control" definition of containment.

**Verification command (passes after remediation).**

```bash
# Both paths must 404; the home page must still 200.
test "$(curl -s -o /dev/null -w %{http_code} http://10.10.20.20:3000/ftp)" = 404 \
  && test "$(curl -s -o /dev/null -w %{http_code} http://10.10.20.20:3000/rest/admin/application-version)" = 404 \
  && test "$(curl -s -o /dev/null -w %{http_code} http://10.10.20.20:3000/)" = 200 \
  && echo "F3 CLOSED"
```

**Before vs after.**

| File | Content |
|---|---|
| `scans/before/08-curl-version.txt` | `HTTP/1.1 200 OK` + `{"version":"20.4.0-SNAPSHOT"}` |
| `scans/after/08-curl-version.txt` | `HTTP/1.1 404 Not Found` from nginx |
| `scans/before/09-curl-ftp.txt` | Full HTML directory listing of 11 files |
| `scans/after/09-curl-ftp.txt` | `HTTP/1.1 404 Not Found` from nginx |

---

### F4 — Gateway exposed SSH and DNS to the lab subnets

**Severity:** High  —  **Likelihood:** Medium (requires an already-compromised
foothold on subnet A or B, but then presents an immediate pivot into the
gateway itself)

**What it is.** The gateway's firewall only filtered the FORWARD chain. The
INPUT chain — traffic destined to the gateway — was left at the default policy
ACCEPT, so a port scan from clientA against the gateway's own subnet-B
interface showed `22/tcp open ssh` and `53/tcp open domain`. An attacker who
had compromised either client could SSH directly into the gateway (the
single trust-anchor of the lab).

**Evidence.** [scans/before/05-nmap-full-tcp-gateway.txt](../scans/before/05-nmap-full-tcp-gateway.txt):

```
PORT   STATE SERVICE
22/tcp open  ssh
53/tcp open  domain
```

**Reproduction.**

```bash
sudo nmap -Pn -sS -p 22,53 10.10.20.10
# before: 22/tcp open, 53/tcp open
```

**Demonstrated impact.** From clientA I could point `ssh` at `10.10.20.10`
and authenticate with any user Juice Shop or a weak client host already
exposed. More importantly, every piece of state on the gateway — the
private SSH key in `/vagrant`, the DNS records, the firewall itself —
becomes accessible if any user on the lab is phished or breached.

**Remediation.** Commit [`c131905`](../remediation/notes.md) adds an INPUT
chain with default DROP, allowing only:

- Replies to the gateway's own outbound connections (conntrack
  `ESTABLISHED,RELATED`).
- Anything on the loopback and on the Vagrant NAT interface (so provisioning
  works).
- UDP/67 DHCP on the subnet-A interface (fix in commit `6bcb042`).
- UDP/53 and TCP/53 DNS from both lab subnets (the gateway is their
  resolver).
- ICMP, so ping and path discovery stay functional.

SSH on 22 is now filtered from both lab subnets.

**Verification command (passes after remediation).**

```bash
sudo nmap -Pn -p 22 10.10.20.10 | grep -E '^22/tcp' | grep -q filtered && echo "F4 CLOSED"
```

**Before vs after.**

| File | Content |
|---|---|
| `scans/before/05-nmap-full-tcp-gateway.txt` | `22/tcp open ssh`, `53/tcp open domain` |
| `scans/after/05-nmap-full-tcp-gateway.txt` | only `53/tcp open domain` — SSH is now filtered |
| `scans/before/12-gateway-iptables-live.txt` | No INPUT chain rules — policy ACCEPT |
| `scans/after/12-gateway-iptables-live.txt` | INPUT policy DROP, with explicit ACCEPTs for DHCP / DNS / ICMP / NAT |

---

### F5 — Weak admin password with MD5 hash leaked in JWT

**Severity:** High  —  **Likelihood:** Medium (requires F1 to acquire a token,
or any authenticated session on the app; cracking is trivial)

**What it is.** Two defects compound here:

1. The administrator account uses the password `admin123` — a top-10 common
   password.
2. Every JWT issued by Juice Shop embeds the user's password hash
   (`password` field) in the base64 payload. The hash is unsalted MD5.

Any legitimate login — and any SQL-injection result from F1 — exposes the
hash to the client. MD5 of `admin123` is `0192023a7bbd73250516f069df18b500`,
which matches without any cracking work:

```
$ echo -n "admin123" | md5sum
0192023a7bbd73250516f069df18b500  -
```

**Evidence.** [scans/before/13-crack-admin-hash.txt](../scans/before/13-crack-admin-hash.txt).
The hash itself is visible in [scans/before/10-curl-sqli-login.txt](../scans/before/10-curl-sqli-login.txt).

**Reproduction.** Take the JWT returned by the F1 exploit, base64-decode the
middle segment, read the `password` field, pass it through `hashcat -m 0` or
simply try `admin123`.

**Demonstrated impact.** The attacker possesses both a valid admin session
and the admin's plaintext password. Password reuse across other systems (a
real-world attacker's primary goal) is now achievable at zero cost.

**Remediation.** Juice Shop ships with `admin123` and the MD5-in-JWT by
design; both are inside the application and out of scope. Containment:

- The rate-limit from F2 blunts brute-force guesses against the admin
  account for attackers who don't have F1.
- No further IaC change. Documented as accepted risk.

**Verification command (fails — accepted).**

```bash
echo -n "admin123" | md5sum | grep -q 0192023a7bbd73250516f069df18b500 && \
  echo "F5 OPEN (accepted — weak default password shipped with service)"
```

---

## 4. Risk rating rationale

Severity reflects the technical blast radius. Likelihood reflects how much an
attacker needs in place first.

| | Severity rationale | Likelihood rationale |
|---|---|---|
| F1 | Full admin takeover of the app with one unauthenticated HTTP request. | One request, no credentials — the only cost is finding the endpoint, which the scan does in seconds. |
| F2 | No direct secret disclosure, but turns every weak-credential issue into a solved one at line rate. | No prerequisites; the primitive is always available from subnet A. |
| F3 | Business-data disclosure; enables further exploits (version → CVE). | Trivially reproduced with `curl`; no authentication. |
| F4 | A pivot into the gateway compromises *every* machine in the lab (the gateway holds the private key that authorizes admin1 on all clients). | Requires a foothold on A or B first — hence Medium, not High. |
| F5 | Password material disclosed + weak default → full account compromise beyond the app itself if reused. | Requires either F1 or a legitimate user session; cracking is zero-effort. |

---

## 5. Remediation

Every change is committed. See [remediation/notes.md](../remediation/notes.md)
for the commit-per-finding mapping.

- `c131905` — gateway firewall: F2 hashlimit + F4 INPUT chain.
- `6bcb042` — gateway firewall: F4 follow-up allowing DHCP so clientA still
  gets an address on rebuild (regression discovered during verification).
- `a81a167` — `login.sh`: give `admin1`/`dev1`/`deploy1` a password so `sudo`
  prompts are answerable.
- `29a641c` — F3 reverse proxy. Juice Shop bound to loopback,
  nginx on `10.10.20.20:3000` returns 404 for `/ftp*` and
  `/rest/admin/application-version`, proxies everything else through.

The two remaining findings (F1, F5) are Juice Shop internals. They are
not patched; they are **contained** at the network layer (firewall
rate-limit, segmentation) and documented.

---

## 6. Verification

The environment was destroyed with `vagrant destroy -f`, rebuilt from code
with `vagrant up`, and the same scan script ([scans/run-scans.sh](../scans/run-scans.sh))
was re-run. Output files are in [scans/after/](../scans/after/).

### Full re-scan evidence

Pair up the identically-named files in `scans/before/` and `scans/after/`.
The relevant pairs:

| Finding | Before | After | Difference |
|---|---|---|---|
| F2 | `11-curl-ratelimit.txt` | `11-curl-ratelimit.txt` | All 10 attempts served → several attempts timed out (000 after 5 s) |
| F3 | `08-curl-version.txt` | `08-curl-version.txt` | `200 OK` + version JSON → `404 Not Found` (from nginx) |
| F3 | `09-curl-ftp.txt` | `09-curl-ftp.txt` | Full HTML directory listing → `404 Not Found` (from nginx) |
| F4 | `05-nmap-full-tcp-gateway.txt` | `05-nmap-full-tcp-gateway.txt` | `22/tcp open ssh` + `53/tcp` → `53/tcp` only |
| F4 | `12-gateway-iptables-live.txt` | `12-gateway-iptables-live.txt` | No INPUT rules → INPUT policy DROP with allowlist |

The remaining scans (`01-04`, `06-07`, `10`) produce the same output before
and after, because the fixes do not change what clientA sees of the lab
topology — the service is still reachable, the SQLi still works, etc. That
is the intended outcome: the four findings that were fixed are either
*infrastructure* findings (F2, F4) or *path-level containment* (F3); the
two findings that remain as accepted-risk are *service* findings that must
still deploy on rebuild per the project rules.

### Targeted one-command verification per finding

Each of the commands below is included for a live audit:

```bash
# F1 — accepted, expected to succeed as exploit:
curl -s -X POST http://10.10.20.20:3000/rest/user/login \
  -H 'Content-Type: application/json' \
  --data-raw "{\"email\":\"' OR 1=1--\",\"password\":\"x\"}" | grep -q token && echo "F1 OPEN (accepted)"

# F2 — fixed; expect rate-limit drops among 25 attempts:
for i in $(seq 1 25); do curl -s --max-time 5 -o /dev/null -w "%{http_code}\n" \
  -X POST http://10.10.20.20:3000/rest/user/login \
  -H 'Content-Type: application/json' -d "{\"email\":\"a@b\",\"password\":\"x$i\"}"; done | grep -c '^000'
# >0 means the rate-limit fired

# F3 — fixed; nginx returns 404 for both paths, app home still 200:
test "$(curl -s -o /dev/null -w %{http_code} http://10.10.20.20:3000/ftp)" = 404 \
  && test "$(curl -s -o /dev/null -w %{http_code} http://10.10.20.20:3000/rest/admin/application-version)" = 404 \
  && test "$(curl -s -o /dev/null -w %{http_code} http://10.10.20.20:3000/)" = 200 \
  && echo "F3 CLOSED"

# F4 — fixed; SSH to the gateway is filtered:
sudo nmap -Pn -p 22 10.10.20.10 | grep -E '^22/tcp' | grep -q filtered && echo "F4 CLOSED"

# F5 — accepted, weak default password:
echo -n admin123 | md5sum | grep -q 0192023a7bbd73250516f069df18b500 && echo "F5 OPEN (accepted)"
```

---

## 7. Accepted risks

Issues known to the assessor and deliberately left unaddressed:

- **`remote_machines_ed25519` private key committed to the repo.** The
  key authorizes `admin1` on every client and is mounted into the gateway at
  `/vagrant/remote_machines_ed25519`. Anyone with repo access has shell on
  every VM. This is the single largest exposure in absolute terms but is
  accepted because the lab topology was built with the assumption that
  repo-readers are trusted; removing the key would require replacing most of
  the provisioning. Noted here so that nobody treats this repository layout
  as a model for production.
- **`AllowUsers *@10.0.2.*` on clientB's sshd** — required for Vagrant
  provisioning via NAT. In production there would be no NAT adapter and this
  clause would be removed.
- **Juice Shop internal bugs (F1, F5).** Service-level fixes forbidden by
  project rules; contained at the network layer where possible (the
  rate-limit addressed brute-force; the SQLi and the MD5-in-JWT are
  structural). F3 was fixable with a reverse proxy and is now closed.

---

## 8. Reproducing this assessment

```bash
git clone <repo>
cd scan
vagrant up                                    # bring up the three VMs
bash scans/run-scans.sh before                # or after, if validating a fix
cat report/assessment.md
```

All scans run from clientA via the gateway as a bastion; see
`scans/run-scans.sh` for the exact SSH options used.

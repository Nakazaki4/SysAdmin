# Runbook: compromised SSH key

**Use when:** a private key that can log in to the fleet is known or suspected
to be exposed: laptop lost or stolen, key committed to a repository, pasted in
a chat, found on a shared drive, or a teammate with a copy has left.

**Goal:** the exposed key stops working on every host, admins keep access the
whole time, and there is a written record of what happened.

**Stay calm, follow the steps, write everything down.** A rotation done in
order is fast. One improvised under stress tends to lock people out or leave
one host behind.

---

## 0. Start the incident log

Open a file (e.g. `incident-YYYYMMDD.md`) and record from now on, with times:

- who reported it, when, and how
- what exactly leaked (which key, where, since when)
- every command you run and its result

## 1. Identify the key

Find the fingerprint of the exposed key, so you know exactly what to remove:

```bash
ssh-keygen -lf ~/.ssh/remote_fleet_ed25519.pub
# 256 SHA256:9VCBW6j7hynfq... fleet (ED25519)
```

Write it in the log. If you only have the leaked public key, run `ssh-keygen -lf`
on that file.

## 2. Assess: was it used?

Before changing anything, see whether the key has already been used, and
from where. With `LogLevel VERBOSE`, every login records the key fingerprint.

On the bastion (all hosts' SSH activity is collected there):

```bash
vagrant ssh gateway
sudo grep 'Accepted publickey' /var/log/remote/admin.log | grep 'SHA256:9VCBW6j7hynfq'
sudo grep 'Accepted publickey' /var/log/auth.log         | grep 'SHA256:9VCBW6j7hynfq'
```

For each login: note the source IP and time. A login from an address that is
not one of the admins' is a **confirmed intrusion**: also follow step 7.

## 3. Rotate: one command

From the repository, on the admin's machine:

```bash
fleet/rotate-key.sh
```

What it does, in this order:

| Step | Action | Why this order |
|---|---|---|
| 1–2 | generate a new key pair | |
| 3 | **add** the new public key on every host, logging in with the old key | access is never lost: both keys work for a moment |
| 4 | swap the files locally (`~/.ssh/remote_fleet_ed25519` is now the new key) | `ssh/ssh_config` and Vagrant use this path |
| 5 | log in to every host **with the new key**, including through the bastion | if any host fails, the script stops and restores the local files: nothing has been removed yet |
| 6 | **remove** the old key from every `authorized_keys` | only once the new key is proven everywhere |
| 7 | try the old key on every host from a clean client | the proof (next step) |
| 8 | delete the old private key, keep its `.pub` as a record | |

If one host is unreachable, the script stops at step 3 or 5 and says which host.
Fix the access (is it running? `fleet/run.sh true`), then run the script again.

### Doing it by hand (if the script can't be used)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/remote_fleet_ed25519.new -C "fleet-$(date +%F)"
NEW=$(cat ~/.ssh/remote_fleet_ed25519.new.pub)
OLD=$(awk '{print $2}' ~/.ssh/remote_fleet_ed25519.pub)

# add new everywhere (old key still works)
fleet/run.sh "echo '$NEW' >> ~/.ssh/authorized_keys"

# switch local files
mv ~/.ssh/remote_fleet_ed25519     ~/.ssh/remote_fleet_ed25519.revoked
mv ~/.ssh/remote_fleet_ed25519.pub ~/.ssh/remote_fleet_ed25519.revoked.pub
mv ~/.ssh/remote_fleet_ed25519.new     ~/.ssh/remote_fleet_ed25519
mv ~/.ssh/remote_fleet_ed25519.new.pub ~/.ssh/remote_fleet_ed25519.pub

# new key works everywhere?  all hosts must be OK before going on
fleet/run.sh true

# remove old everywhere
fleet/run.sh "grep -vF '$OLD' ~/.ssh/authorized_keys > ~/.ssh/ak && cat ~/.ssh/ak > ~/.ssh/authorized_keys && rm ~/.ssh/ak"
```

## 4. Prove the old key is dead

The script prints, for every host:

```
  bastion:  old key refused (Permission denied (publickey))
  client-a: old key refused (Permission denied (publickey))
  client-b: old key refused (Permission denied (publickey))
```

The test uses a **clean client**: `-F /dev/null` (no config), no agent,
`IdentitiesOnly=yes`, and only the old key. Otherwise ssh could silently fall
back to the new key and the test would prove nothing. To repeat it by hand:

```bash
# bastion
ssh -F /dev/null -o IdentitiesOnly=yes -o IdentityAgent=none \
    -i ~/.ssh/remote_fleet_ed25519.revoked ops@192.168.56.10 true
# internal host (reach the bastion with the NEW key, try the OLD one on the target)
ssh -F /dev/null -o IdentitiesOnly=yes -o IdentityAgent=none \
    -o "ProxyCommand=ssh -F ssh/ssh_config -W %h:%p bastion" \
    -i ~/.ssh/remote_fleet_ed25519.revoked ops@10.10.10.20 true
```

Both must end with `Permission denied (publickey)`. Also check no host still
lists the old key:

```bash
fleet/run.sh "grep -c '$OLD' ~/.ssh/authorized_keys || true"     # every host: 0
```

## 5. Make it permanent

- `Vagrantfile` installs `~/.ssh/remote_fleet_ed25519.pub` at provisioning.
  After rotation that file is the new key, so `vagrant provision` or a rebuild
  can't bring the old key back.
- Hand the new private key to the other admins through a secure channel
  (never by email or chat), and make sure everyone deletes old copies.
- Search for other places the old key might be trusted: other servers,
  Git hosting, CI secrets.

## 6. Close the incident

Write in the log:

- old fingerprint (revoked) and new fingerprint (active)
- time the old key stopped working on each host
- result of step 2 (used or not, from where)
- how the key leaked, and what changes so it can't happen again
  (passphrase on keys, key in an agent instead of a file, hardware key,
  shorter key lifetime)

## 7. If the key was used by someone else

A rotation stops future logins. It does not undo what an intruder did with the
access they had:

- check the central logs for what the session did:
  `grep -E 'sudo|session opened' /var/log/remote/admin.log`
- look for persistence: other keys in any `authorized_keys`, new users,
  cron jobs, changed sudoers
- the reliable fix for a compromised host is to **rebuild it from code**
  (`vagrant destroy -f client-a && vagrant up client-a`), not to clean it by hand
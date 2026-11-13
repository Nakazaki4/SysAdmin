#!/usr/bin/env bash
# verify.sh - check the /srv/shared and /srv/scratch permissions.
# Creates 4 temporary test users, runs the checks, then deletes them.
# Usage: sudo ./verify.sh

SHARED=/srv/shared
SCRATCH=/srv/scratch
PASS=0
FAIL=0

# Run a command as a user; expect it to succeed (yes) or fail (no).
check() {
  expect=$1 user=$2 desc=$3 cmd=$4
  if runuser -u "$user" -- sh -c "$cmd" >/dev/null 2>&1; then got=yes; else got=no; fi
  if [ "$got" = "$expect" ]; then
    echo "PASS  $desc"; PASS=$((PASS + 1))
  else
    echo "FAIL  $desc"; FAIL=$((FAIL + 1))
  fi
}

# --- test users ---
useradd -M -G admin,shared  t_admin
useradd -M -G developer,shared t_dev
useradd -M -G deploy t_deploy
useradd -M t_other

cleanup() {
  rm -f "$SHARED"/t_*.txt "$SCRATCH"/t_*.txt
  for u in t_admin t_dev t_deploy t_other; do userdel "$u" 2>/dev/null; done
}
trap cleanup EXIT

echo "== Shared directory =="
check yes t_admin  "admin creates a file (umask 022)"  "umask 022; echo a > $SHARED/t_admin.txt"
check yes t_dev    "developer creates a file (umask 077)" "umask 077; echo d > $SHARED/t_dev.txt"
check yes t_dev    "developer edits admin's file"  "echo x >> $SHARED/t_admin.txt"
check yes t_admin  "admin edits developer's file"  "echo x >> $SHARED/t_dev.txt"
check yes t_deploy "deploy reads a file"           "cat $SHARED/t_admin.txt"
check no  t_deploy "deploy cannot edit a file"     "echo x >> $SHARED/t_admin.txt"
check no  t_deploy "deploy cannot create a file"   "touch $SHARED/t_deploy.txt"
check no  t_other  "outsider cannot list"          "ls $SHARED"
check no  t_other  "outsider cannot read"          "cat $SHARED/t_admin.txt"

echo "== Scratch directory =="
check yes t_dev   "user creates a file"            "echo s > $SCRATCH/t_dev.txt"
check no  t_other "other user cannot delete it"    "rm -f $SCRATCH/t_dev.txt"
check yes t_dev   "owner deletes own file"         "rm $SCRATCH/t_dev.txt"


echo "== SSH =="
# sshd -T shows the settings sshd actually uses.
check_root yes "password login is off"        "sshd -T | grep -qx 'passwordauthentication no'"
check_root yes "keyboard-interactive is off"  "sshd -T | grep -qx 'kbdinteractiveauthentication no'"
check_root yes "root login is off"            "sshd -T | grep -qx 'permitrootlogin no'"
 
# Connect to ourselves without a key: the server must only offer "publickey".
check_root yes "server only accepts keys" \
  "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o PubkeyAuthentication=no nobody@localhost 2>&1 |
   grep -q 'Permission denied (publickey)'"
 
# Every user who can log in (UID 1000+, real shell) needs an authorized_keys file.
while read -r u home; do
  case "$u" in t_*) continue ;; esac
  check_root yes "$u has an SSH key" "[ -s $home/.ssh/authorized_keys ]"
done < <(awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false)$/ {print $1, $6}' /etc/passwd)
 
echo

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]


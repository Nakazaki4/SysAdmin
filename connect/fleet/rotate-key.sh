
#!/bin/bash
# set -euo pipefail

KEY="${KEY:-$HOME/.ssh/remote_machines_ed25519}"
NEW="$KEY.new"
OLD="$KEY.old"
HOSTS="${HOSTS:-bastion client-a client-b}"
LOG="$HOME/ssh/ssh-key-incident.log"

# 1. Check prerequisites
if [[ ! -f "$KEY" || ! -f "$KEY.pub" ]]; then
    echo "Error: Old key pair not found."
    exit 1
fi

if [[ -e "$NEW" || -e "$NEW.pub" || -e "$OLD" || -e "$OLD.pub" ]]; then
    echo "Error: New or backup key already exists."
    exit 1
fi

mkdir -p "$(dirname "$LOG")"

# 2. Record old key fingerprint
echo "=== SSH key rotation: $(date) ===" >> "$LOG"
ssh-keygen -lf "$KEY.pub" >> "$LOG"

OLD_BLOB=$(awk '{print $2}' "$KEY.pub")

# 3. Generate new key pair
echo "Generating new key..."
ssh-keygen -q -t ed25519 -N '' -C "remote_machines" -f "$NEW"

# 4. Install new public key on all hosts
for h in $HOSTS; do
    echo "Installing new key on $h..."
    ssh-copy-id -i "$NEW.pub" "$h"
done

# 5. Test new key on all hosts
for h in $HOSTS; do
    echo "Testing new key on $h..."
    ssh -i "$NEW" -o IdentitiesOnly=yes "$h" true
done

echo "New key works on every host."

# 6. Remove old public key from remote authorized_keys
for h in $HOSTS; do
    echo "Removing old key from $h..."

    ssh -i "$NEW" -o IdentitiesOnly=yes "$h" \
        "OLD_BLOB='$OLD_BLOB' bash -s" <<'REMOTE'

set -euo pipefail

AUTH="$HOME/.ssh/authorized_keys"

if [[ ! -f "$AUTH" ]]; then
    echo "Error: authorized_keys not found."
    exit 1
fi

# Backup authorized_keys before modifying it
cp -p "$AUTH" "$AUTH.bak.$(date +%Y%m%d%H%M%S)"

# Remove lines containing the old public key
TMP=$(mktemp "$HOME/.ssh/authorized_keys.XXXXXX")

awk -v blob="$OLD_BLOB" '
{
    remove = 0

    for (i = 1; i <= NF; i++) {
        if ($i == blob) {
            remove = 1
            break
        }
    }

    if (!remove) print
}
' "$AUTH" > "$TMP"

chmod 600 "$TMP"
mv "$TMP" "$AUTH"

REMOTE

done

# 7. Test new key again after removing old keys
for h in $HOSTS; do
    echo "Final authentication test: $h..."
    ssh -i "$NEW" -o IdentitiesOnly=yes "$h" true
done

# 8. Replace local keys, keeping old keys as backups
echo "Replacing local keys..."

mv "$KEY" "$OLD"
mv "$KEY.pub" "$OLD.pub"

mv "$NEW" "$KEY"
mv "$NEW.pub" "$KEY.pub"

echo "SSH key rotation completed successfully."
echo "Old keys backed up at: $OLD and $OLD.pub"
echo "Incident log: $LOG"

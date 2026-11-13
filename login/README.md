## Shared directory: /srv/shared

```bash
sudo groupadd shared
sudo groupadd admin
sudo groupadd developer
sudo groupadd deploy

# Admins and developers join "shared"; deploy does not
sudo usermod -aG admin,shared admin1
sudo usermod -aG developer,shared dev1
sudo usermod -aG deploy deploy1

sudo mkdir -p /srv/shared
sudo chown root:shared /srv/shared

# 2 = setgid: new files get group "shared", not the creator's group
# 770 = shared group full access, others nothing
sudo chmod 2770 /srv/shared

# Access ACL: deploy may read and enter, not write
sudo setfacl -m g:deploy:r-x /srv/shared

# Default ACL: copied onto every new file/subdir. While it exists,
# the creator's umask is ignored, so new files are always group-writable
sudo setfacl -d -m u::rwx,g::rwx,g:deploy:r-x,o::--- /srv/shared
```

## Scratch directory: /srv/scratch

```bash
sudo mkdir -p /srv/scratch
# 777 = anyone can create files
# 1 = sticky bit: only a file's owner can delete or rename it
sudo chmod 1777 /srv/scratch
```

## Which mechanism, where, and why

| Requirement | Mechanism | Why |
|---|---|---|
| admin + developer read/write | group `shared` + mode `770` | Standard permissions handle one group; both roles are in it |
| New files get group `shared` | setgid bit | Otherwise a file gets the creator's own group |
| New files editable by the group | default ACL `g::rwx` | setgid sets the group but not its rights; with umask `022` files would be read-only for the group. A default ACL overrides the umask |
| deploy read only | ACL `g:deploy:r-x` | Only one group slot exists in standard permissions |
| Everyone else: nothing | `other::---` | Standard permissions express this |
| Scratch: delete only own files | sticky bit | With plain `777`, anyone could delete anyone's file |

## SSH
h=host
```bash
for user in admin1 dev1 deploy1; do
   ssh-copy-id "$user"@"$host"
   sudo tee /etc/ssh/sshd_config.d/00-keys-only.conf <<'EOF'
   PubkeyAuthentication yes
   PasswordAuthentication no
   KbdInteractiveAuthentication no
   PermitRootLogin no
   EOF 
done
```

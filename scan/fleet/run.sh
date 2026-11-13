#!/usr/bin/env bash
#
#   fleet/run.sh update             apply package updates (apt) everywhere
#   fleet/run.sh logs               collect the last 24 h of SSH + sudo logs
#   fleet/run.sh '<command>'        run any shell command everywhere
#
#   HOSTS="client-a" fleet/run.sh uptime     limit to some hosts
#
# Full output of each host: fleet/output/<timestamp>/<host>.log
# cd "$(dirname "$0")/.." || exit 1

HOSTS="${HOSTS:-bastion client-a client-b}"
SSH=(ssh -F ssh/ssh_config -o BatchMode=yes -o ConnectTimeout=10)

# [ $# -ge 1 ] || { sed -n '2,12p' "$0"; exit 2; }

case "$1" in
  update)
    TASK="package updates"
    CMD='sudo env DEBIAN_FRONTEND=noninteractive apt-get update -q &&
         sudo env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q &&
         echo "upgraded; reboot needed: $([ -f /var/run/reboot-required ] && echo yes || echo no)"' ;;
  logs)
    TASK="collect SSH + sudo logs (24 h)"
    CMD='sudo journalctl --since "24 hours ago" --no-pager _SYSTEMD_UNIT=ssh.service + _COMM=sudo' ;;
  *)
    TASK="$*"
    CMD="$*" ;;
esac

OUT="fleet/output/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
echo "Task: $TASK"
echo "Hosts: $HOSTS"
echo

# Start every host at once; each writes its output, exit code and duration
for h in $HOSTS; do
  (
    start=$(date +%s)
    "${SSH[@]}" "$h" "$CMD" > "$OUT/$h.log" 2>&1
    echo "$? $(( $(date +%s) - start ))" > "$OUT/$h.status"
  ) &
done
wait

# Per-host report
failed=0
printf '%-10s %-6s %5s  %s\n' HOST RESULT TIME "LAST LINE"
for h in $HOSTS; do
  read -r rc secs < "$OUT/$h.status"
  last=$(grep -v '^\s*$' "$OUT/$h.log" | tail -n 1 | cut -c1-60)
  if [ "$rc" -eq 0 ]; then res=OK; else res="FAIL($rc)"; failed=$((failed + 1)); fi
  printf '%-10s %-6s %4ss  %s\n' "$h" "$res" "$secs" "$last"
done

echo
echo "Full output: $OUT/"
[ "$failed" -eq 0 ] && echo "All hosts OK." || echo "$failed host(s) failed."
exit "$failed"
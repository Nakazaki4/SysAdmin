#!/bin/sh
VM="${VM-bastion}"
usage() {
	echo "Usage: $0 take [lable] | list | restore NAME | delete NAME" >&2
	exit 2
}

case "${1:-}" in
	take)
		name="$(date +%Y%m%d-%H%M)-${2:-manual}"
		vagrant snapshot save "$VM" "$name"
		echo "Snapshot saved: $name"
		;;
	list)
		vagrant snapshot list "$VM"
		;;
	restore)
		[ -n "${2:-}"] || usage
		vagrant snapshot restore --no-provision "$VM" "$2"
		echo "Restored: $2 (now run your checks, e.g verify.sh)"
		;;
	delete)
		[ -n "${2:-}"] || usage
		vagrant snapshot delete "$VM" "$2"
		;;
	*)
		usage
		;;
esac

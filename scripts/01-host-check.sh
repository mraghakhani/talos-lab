#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=./scripts/lib.sh
source "$(dirname "$0")/lib.sh"

failed=0

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'OK   %-24s %s\n' "$1" "$(command -v "$1")"
  else
    printf 'FAIL %-24s missing\n' "$1"
    failed=1
  fi
}

log "Checking CPU/KVM support"
if [[ -e /dev/kvm ]]; then
  echo "OK   /dev/kvm exists"
else
  echo "FAIL /dev/kvm is missing"
  failed=1
fi

if grep -qw vmx /proc/cpuinfo; then
  echo "OK   Intel VT-x (vmx) is exposed"
else
  echo "FAIL Intel VT-x flag (vmx) not found"
  failed=1
fi

if lsmod | grep -q '^kvm_intel'; then
  echo "OK   kvm_intel kernel module loaded"
else
  echo "WARN kvm_intel is not currently visible in lsmod"
fi

log "Checking required commands"
for cmd in virsh virt-install qemu-img qemu-system-x86_64 dnsmasq curl talosctl yq envsubst sha256sum; do
  check_cmd "$cmd"
done

log "Checking libvirt system connection"
if virsh -c "$LIBVIRT_URI" uri >/dev/null 2>&1; then
  echo "OK   libvirt connection: $LIBVIRT_URI"
else
  echo "FAIL cannot connect to $LIBVIRT_URI"
  echo "     Start libvirt's QEMU socket/service and ensure your user is authorized."
  failed=1
fi

log "Checking route overlap"
if ip route | grep -Fq "$LAB_NETWORK"; then
  if ip route | grep -F "$LAB_NETWORK" | grep -Fq "$LAB_BRIDGE"; then
    echo "OK   $LAB_NETWORK already belongs to expected bridge $LAB_BRIDGE"
  else
    echo "FAIL $LAB_NETWORK already exists on an unexpected interface"
    ip route | grep -F "$LAB_NETWORK" || true
    failed=1
  fi
else
  echo "OK   $LAB_NETWORK is not present in the current route table"
fi

exit "$failed"

#!/usr/bin/env bash
set -euo pipefail

packages=(
  go-task
  qemu-base
  libvirt
  virt-install
  dnsmasq
  iptables-nft
  edk2-ovmf
  gettext
  go-yq
  curl
)

sudo pacman -S --needed "${packages[@]}"

echo
echo "Installed host virtualization dependencies."
echo "talosctl and kubectl remain separately versioned cluster tooling."

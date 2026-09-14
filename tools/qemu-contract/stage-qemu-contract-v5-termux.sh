#!/data/data/com.termux/files/usr/bin/bash
# Stages the v5 collector into a new copy of the historical disposable QEMU ESP.
set -euo pipefail

export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:/system/bin"
# The deliberately minimal QEMU ESP has zero CHS geometry.  This disables only
# mtools' legacy geometry warning; FAT allocation and writes stay mtools-owned.
export MTOOLS_SKIP_CHECK=1

V4=/sdcard/Download/qemu-contract-20260913-v4
V5=/sdcard/Download/qemu-contract-20260914-v5

[[ -r "$V4/qemu-contract-fat.img" && -r "$V5/QemuContractProbe.efi" ]] || exit 2
[[ ! -e "$V5/qemu-contract-vars.raw" && ! -e "$V5/qemu-contract-raw-serial.log" ]] || exit 3

cp "$V4/qemu-contract-fat.img" "$V5/qemu-contract-fat.img"
mcopy -o -i "$V5/qemu-contract-fat.img" "$V5/QemuContractProbe.efi" ::/EFI/BOOT/BOOTAA64.EFI
mdir -i "$V5/qemu-contract-fat.img" ::/EFI/BOOT
sha256sum "$V5/qemu-contract-fat.img" "$V5/QemuContractProbe.efi"

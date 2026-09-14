#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:/system/bin"
IMG=/sdcard/Download/qemu-contract-20260913-v4/qemu-contract-fat.img
ls -l "$IMG"
od -An -tx1 -N96 "$IMG"
MTOOLS_SKIP_CHECK=1 mdir -i "$IMG" ::/EFI/BOOT

#!/data/data/com.termux/files/usr/bin/bash
# QEMU-only accepted-platform-contract collector, revision v5.
# Run explicitly under `adb shell run-as com.termux`.
# It uses a new disposable ESP/variable store and never opens the product image.
set -euo pipefail

export HOME=/data/user/0/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:/system/bin"

ROOT=/sdcard/Download/qemu-contract-20260914-v5
CODE="$PREFIX/share/edk2/aarch64/QEMU_EFI-pflash.raw"
VARS_TEMPLATE="$PREFIX/share/edk2/aarch64/vars-template-pflash.raw"
ESP="$ROOT/qemu-contract-fat.img"
VARS="$ROOT/qemu-contract-vars.raw"
SERIAL="$ROOT/qemu-contract-raw-serial.log"
STDERR="$ROOT/qemu-contract-qemu.stderr.log"
STATUS="$ROOT/qemu-contract-exit-status.txt"

[[ -r "$CODE" && -r "$VARS_TEMPLATE" && -r "$ESP" ]] || {
  echo 'missing QEMU firmware or staged disposable ESP' > "$STDERR"
  exit 2
}
[[ ! -e "$VARS" && ! -e "$SERIAL" && ! -e "$STDERR" && ! -e "$STATUS" ]] || {
  echo 'refusing to overwrite a prior v5 contract artifact' >&2
  exit 3
}

cp "$VARS_TEMPLATE" "$VARS"
set +e
/system/bin/timeout 90 "$PREFIX/bin/qemu-system-aarch64" \
  -machine virt,highmem=on,gic-version=3,its=on,virtualization=on \
  -accel tcg,thread=multi -cpu cortex-a76 -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file="$CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive if=none,id=esp,format=raw,readonly=on,file="$ESP" \
  -device virtio-blk-pci,drive=esp,bootindex=1 \
  -device ramfb -nic none -display none -monitor none \
  -serial file:"$SERIAL" > "$STDERR" 2>&1
rc=$?
set -e
printf '%s\n' "$rc" > "$STATUS"
exit "$rc"

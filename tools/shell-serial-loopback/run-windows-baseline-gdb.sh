#!/system/bin/sh
# Exactly one disposable, read-only shell AVF GDB capture.  The VM waits for
# a GDB client; this runner never writes guest storage.
set -u
work=/data/local/tmp/winavf-shell-gdb-pc-20260909
console="$work/raw-serial.bin"
vm_out="$work/vm.stdout-stderr.log"
crosvm_log="$work/crosvm.log"
: > "$console"
: > "$vm_out"
: > "$crosvm_log"
rm -f "$work/vm.exit"
timeout -k 5 115 /apex/com.android.virt/bin/vm run \
  --name winavf-shell-gdb-pc-20260909 \
  --debug full \
  --gdb 4567 \
  --console "$console" \
  --log "$crosvm_log" \
  "$work/vm-config.json" >"$vm_out" 2>&1
rc=$?
printf 'VM_EXIT=%s\n' "$rc" > "$work/vm.exit"
exit "$rc"

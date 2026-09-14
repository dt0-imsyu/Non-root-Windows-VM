#!/system/bin/sh
# Text-safe ADB RX relay. base64 input is decoded to a raw foreground pipe;
# vm run duplicates that pipe because --console-in is deliberately omitted.
set -u

work=/data/local/tmp/winavf-shell-t-base64-loopback-20260907
console="$work/uart-output-raw.bin"
vm_log="$work/vm-run.stdout-stderr.log"

: > "$console"
: > "$vm_log"
tail -c +1 -f "$console" 2>"$work/tail.stderr.log" &
tail_pid=$!

base64 -di | timeout -k 5 30 /apex/com.android.virt/bin/vm run \
  --name winavf-shell-t-base64-loopback-20260907 \
  --console "$console" \
  "$work/vm-config.json" >"$vm_log" 2>&1
vm_rc=$?

kill "$tail_pid" 2>/dev/null || true
wait "$tail_pid" 2>/dev/null || true
printf 'VM_EXIT=%s\n' "$vm_rc" > "$work/vm.exit"
exit "$vm_rc"

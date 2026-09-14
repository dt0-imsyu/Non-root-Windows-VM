#!/system/bin/sh
# Foreground vm run is deliberate: the shell must retain its socket stdin.
# Do not add --console-in; vm run duplicates stdin in that mode.
set -u

work=/data/local/tmp/winavf-shell-t-loopback-20260907
console="$work/uart-output-raw.bin"
vm_log="$work/vm-run.stdout-stderr.log"
tail_log="$work/tail.stderr.log"

: > "$console"
: > "$vm_log"
: > "$tail_log"

tail -c +1 -f "$console" 2>"$tail_log" &
tail_pid=$!

timeout -k 5 30 /apex/com.android.virt/bin/vm run \
  --name winavf-shell-t-loopback-20260907 \
  --console "$console" \
  "$work/vm-config.json" >"$vm_log" 2>&1
vm_rc=$?

kill "$tail_pid" 2>/dev/null || true
wait "$tail_pid" 2>/dev/null || true
printf 'VM_EXIT=%s\n' "$vm_rc" > "$work/vm.exit"
exit "$vm_rc"

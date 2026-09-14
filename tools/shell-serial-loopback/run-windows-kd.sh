#!/system/bin/sh
# One shell-owned Windows KD diagnostic. stdin is inherited as the raw COM1 RX
# stream; guest UART TX is copied to stdout by tail without a PTY.
set -u

work=/data/local/tmp/winavf-kd-shell-20260907
console="$work/raw-serial-tx.bin"
vm_out="$work/vm.stdout-stderr.log"
crosvm_log="$work/crosvm.log"
exit_file="$work/vm.exit"

: > "$console"
: > "$vm_out"
: > "$crosvm_log"
rm -f "$exit_file"

(
  timeout -k 5 100 /apex/com.android.virt/bin/vm run \
    --name winavf-kd-shell-20260907 \
    --console "$console" \
    --console-in /proc/self/fd/0 \
    --log "$crosvm_log" \
    "$work/vm-config.json" >"$vm_out" 2>&1
  printf '%s\n' "$?" > "$exit_file"
) &
vm_pid=$!

# This is the sole stdout producer. Toybox tail copies bytes; it is not a PTY.
tail -c +1 -f "$console" &
tail_pid=$!

wait "$vm_pid"
vm_wait=$?
kill "$tail_pid" 2>/dev/null || true
wait "$tail_pid" 2>/dev/null || true
exit "$vm_wait"

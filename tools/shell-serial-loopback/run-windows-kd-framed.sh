#!/system/bin/sh
# Disposable shell-owned Windows KD VM.  ADB carries Base64 text; crosvm sees
# only raw UART through its inherited anonymous stdin pipe.
set -u
work=/data/local/tmp/winavf-kd-shell-framed-20260907
console="$work/raw-serial-tx.bin"
vm_out="$work/vm.stdout-stderr.log"
crosvm_log="$work/crosvm.log"
: > "$console"
: > "$vm_out"
: > "$crosvm_log"
rm -f "$work/vm.exit"
"$work/console-file-base64-tailer" "$console" &
tailer_pid=$!
base64 -di | timeout -k 5 100 /apex/com.android.virt/bin/vm run \
  --name winavf-kd-shell-framed-20260907 \
  --console "$console" \
  --log "$crosvm_log" \
  "$work/vm-config.json" >"$vm_out" 2>&1
rc=$?
sleep 1
kill "$tailer_pid" 2>/dev/null || true
wait "$tailer_pid" 2>/dev/null || true
printf 'VM_EXIT=%s\n' "$rc" > "$work/vm.exit"
exit "$rc"

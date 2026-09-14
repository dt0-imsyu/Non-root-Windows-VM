#!/system/bin/sh
# ADB carries Base64 ingress and O:<base64> egress records; crosvm receives
# raw UART bytes.  Ingress deliberately uses an anonymous pipe: shell SELinux
# denies mkfifo(2) under /data/local/tmp.
set -eu
work=/data/local/tmp/winavf-shell-t-framed-loopback-20260907
console="$work/uart-output-raw.bin"
: > "$console"
"$work/console-file-base64-tailer" "$console" &
tailer_pid=$!
# The foreground pipeline makes crosvm inherit a pollable anonymous pipe;
# there is intentionally no --console-in path argument.
set +e
base64 -di | timeout -k 5 30 /apex/com.android.virt/bin/vm run \
  --name winavf-shell-t-framed-loopback-20260907 \
  --console "$console" \
  "$work/vm-config.json" >"$work/vm-run.stdout-stderr.log" 2>&1
rc=$?
set -e
# The guest can shut down immediately after its final UART write.  Give the
# regular-file tailer one bounded polling interval to drain that final block.
sleep 1
kill "$tailer_pid" 2>/dev/null || true
wait "$tailer_pid" 2>/dev/null || true
printf 'VM_EXIT=%s\n' "$rc" > "$work/vm.exit"
exit "$rc"

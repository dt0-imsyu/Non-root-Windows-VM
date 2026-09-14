#!/system/bin/sh
# Disposable AVF UART loopback using an inherited anonymous pipe.  `vm run`
# opens /proc/self/fd/0 as --console-in, so crosvm receives a pollable pipe,
# not a regular file or a PTY.
set -eu

work="$1"
name="$2"
image="$work/winavf-shell-serial-loopback.Image"
config="$work/vm-config.json"
payload="$work/uart-input-4096.bin"
output="$work/uart-output-raw.bin"
vm_log="$work/vm-run.stdout-stderr.log"
writer_log="$work/pipe-writer.log"

rm -f "$output" "$vm_log" "$writer_log"
: > "$output"

# The producer keeps the write end open but sends no data until the separate
# guest-output file contains readiness.  Consequently the crosvm input thread
# is live before byte zero is sent.
(
  i=0
  while [ "$i" -lt 100 ]; do
    if grep -q 'SHELL_SERIAL_LOOPBACK_READY' "$output" 2>/dev/null; then
      echo 'PIPE_WRITER=MARKER_SEEN' >&2
      cat "$payload"
      sleep 2
      exit 0
    fi
    i=$((i + 1))
    sleep 0.1
  done
  echo 'PIPE_WRITER=MARKER_TIMEOUT' >&2
  exit 2
) 2>"$writer_log" |
  timeout 30 /apex/com.android.virt/bin/vm run \
    --name "$name" \
    --console "$output" \
    --console-in /proc/self/fd/0 \
    "$config" >"$vm_log" 2>&1
vm_rc=$?

printf 'VM_EXIT=%s\n' "$vm_rc"
exit 0

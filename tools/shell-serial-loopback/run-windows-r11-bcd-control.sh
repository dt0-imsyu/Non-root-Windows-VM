#!/system/bin/sh
# One bounded shell-only control: r11 firmware, baseline BCD, no KD bridge.
set -u
work=/data/local/tmp/winavf-shell-r11-bcd-control-20260908
console="$work/raw-serial.bin"
vm_out="$work/vm.stdout-stderr.log"
crosvm_log="$work/crosvm.log"
: > "$console"
: > "$vm_out"
: > "$crosvm_log"
rm -f "$work/vm.exit"
timeout -k 5 100 /apex/com.android.virt/bin/vm run \
  --name winavf-shell-r11-bcd-control-20260908 \
  --console "$console" \
  --log "$crosvm_log" \
  "$work/vm-config.json" >"$vm_out" 2>&1
rc=$?
printf 'VM_EXIT=%s\n' "$rc" > "$work/vm.exit"
exit "$rc"

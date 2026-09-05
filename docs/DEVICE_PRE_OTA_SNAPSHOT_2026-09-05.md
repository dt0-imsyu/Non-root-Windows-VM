# Read-only device snapshot before pending Samsung reboot

Captured on 2026-09-05 before the already-downloaded security update is
installed. This record contains no system-image extraction and no user data.

| Field | Value |
| --- | --- |
| Device | Samsung SM-X736B / `gts11` |
| Android | 16, API `36.1` |
| Fingerprint | `samsung/gts11xx/gts11:16/BP4A.251205.006/X736BXXS6BZF4_OXM6BZF4:user/release-keys` |
| Security patch | 2026-06-05 |
| One UI | `80500` |
| PDA/build | `X736BXXS6BZF4` |
| SELinux | enforcing; ADB identity `u:r:shell:s0` |
| AVF APEX | `com.android.virt` present |
| VmTerminalApp | `com.android.virtualization.terminal`, version 16 / code 36, privileged APEX app; currently stopped/disabled by Settings |
| WinAVF | `com.example.winavf`, UID 10441, `u:r:untrusted_app:s0:...` |
| WinAVF permissions | `MANAGE_VIRTUAL_MACHINE=granted`, `USE_CUSTOM_VIRTUAL_MACHINE=granted` |
| Runtime processes | no active crosvm or WinAVF VM at capture time |

## AVF/display facts at capture

- Public VM classes expose `DisplayConfig`, `GpuConfig`, console and vsock
  methods, but no `Surface`, framebuffer, GPU-resource, FD, dma-buf, or
  AHardwareBuffer-return method.
- The opt-in app audit again saw
  `android.system.virtualizationservice=NULL` and no internal display AIDL
  classes. This is the expected ordinary-app boundary, not evidence that the
  daemon is absent.
- Shell observation found the `com.android.virt` APEX and the virtualization
  service registration, but enforcing SELinux prevents shell inspection of
  crosvm internals. No unsupported inspection was attempted.

## Local evidence integrity

The raw text files remain outside Git at
`%LOCALAPPDATA%\\Temp\\winavf-graphics-pre-ota`:

| File | SHA-256 |
| --- | --- |
| `device-runtime-snapshot.txt` | `EE5FC1CB75BEA106F1FFDCE2CE22A80D81608179F2E8023E92ABEDD6D7AC339D` |
| `avf-capability-audit.txt` | `348940A000DB79BC3587D53D22914445AD487501D7D2D6D6767B2AEAF7D8169B` |
| `native-avf-display-access-audit-current.txt` | `C2693185EE2911AFCB8ACC94A0EBD06AA623D523875AFFA4C7FF3ACCD6EF37A6` |

After the reboot, repeat precisely these read-only observations and compare
the table plus the three file hashes. Do not alter the OTA, slots, recovery,
APEX, SELinux policy, firmware, or Windows media.

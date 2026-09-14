# WinAVF Astra first pass - 2026-09-05

## Reconstructed architecture

The verified path is Android app -> AVF VirtualizationService -> system
crosvm -> GenieZone -> kernel-first firmware -> U-Boot -> second-stage EDK2 ->
Microsoft `BOOTAA64.EFI`/Windows Boot Manager -> `boot.wim`. PCI root bridge,
virtio-blk and virtio-gpu enumeration, WIM load, and the original
`ExitBootServices()` return are proven. The last externally observable marker
is the post-return `ER` marker emitted by EDK2.

The intended product display path is different from the privileged Terminal
path: WinPE `viogpudo`/`viosock` -> a guest-side relay -> public AVF vsock -> an
app-owned Android Surface. The Terminal `DisplayProvider` path exists on the
device, but its Binder service is restricted to the privileged/platform-signed
domain.

## Evidence classification

**Proven:** AVF/GenieZone launch; kernel-first entry; U-Boot and EDK2; Windows
Boot Manager; `boot.wim` read; PCI/virtio enumeration; GPU-enabled loader; EBS
return; transactional WIM/FAT transport and rollback; production signatures of
the ARM64 virtio packages; privileged Android display service on the device.

**Inferred only:** that `ntoskrnl` entered phase 0/1; that SYSTEM hive
consumption completed; that BOOT_START drivers were accepted or loaded; that
SMSS, `wpeinit`, `startnet.cmd`, or WinPE PnP ran. The three runtime probes all
ended at `ER` without an independent post-EBS signal.

**Blocked:** custom BOOT_START marker under current Code Integrity; KD/bootdebug
because AVF exposes console output but no writable console endpoint; direct
native AVF scanout because `untrusted_app` cannot find the privileged
`virtualizationservice` Binder; signed-driver UART instrumentation.

**Unknown:** the first Windows kernel instruction after loader handoff and
whether the current image fails before or during kernel initialization.

## Early-Windows observability candidates

| Candidate | Stage proved / effect | Pre-filesystem | CI or signed patch | Rollback / ambiguity / cost |
|---|---|---:|---|---|
| Boot Status Data / `BOOTSTAT.DAT` | Boot Manager/loader policy and failure counters; no kernel phase | No | None, but loader-side only | Trivial; cannot distinguish EBS from kernel entry; low |
| BCD `bootlog` / `ntbtlog.txt` | Kernel boot-driver enumeration if the log is written | No | BCD setting only | Reversible; WinPE log is normally on RAM-backed `X:` and may vanish; medium |
| BCD `bootdebug` + KD | Winload/kernel debugger handshake and phase-level text | No | No binary patch, but requires BCD and duplex transport | Reversible; current AVF input API is absent, so no valid run; high |
| EMS | Loader/kernel serial text through EMS | No | BCD setting only | Reversible; current serial is output-only and prior EMS A/B was non-informative; medium |
| Crash dump / bugcheck artifact | Kernel reached the configured crash path | Usually no | Requires deliberate failure trigger | Rollback possible but destructive to VM state and storage-dependent; high |
| Recovery/failover counters | Boot Manager recovery transition after a failed boot | No | BCD/recovery configuration | Reversible; does not identify the failing phase; medium |
| Existing signed boot-driver configuration | At most service selection/start policy | No | No patch | Trivial; no unique observable side effect; low |
| EFI variable/RTC/watchdog side effect | Firmware-visible state change | Runtime only | None | Trivial if available; no Windows contract guarantees a phase-specific write; low |
| Persistent pre-`wpeinit` file | User-mode marker before `wpeinit` | No | WIM file only | Trivial; requires a writable mounted persistent volume, which was not demonstrated; low |

The only candidate with useful phase resolution is KD/bootdebug, but it is
currently impossible to execute meaningfully. `bootlog` is the best
configuration-only fallback, yet the current WinPE layout provides no durable
post-run sink and therefore cannot be treated as a pass/fail boundary.

## Best next step

No new tablet runtime patch is justified under the present evidence. The exact
next experiment, once a writable AVF console endpoint exists, is a disposable
BCD `bootdebug` + COM1 A/B on the immutable baseline clone: capture the raw
binary handshake, then restore BCD and verify the baseline hash. This uses only
Microsoft-signed components and separates loader handoff from kernel debugger
initialization. Until duplex I/O is proven byte-for-byte with U-Boot, do not
apply BCD or bootdebug.

If duplex console access remains unavailable, the highest-value offline task is
to build a persistence audit for `bootlog` on a deliberately mounted writable
system volume; do not claim that a missing `ntbtlog.txt` means kernel failure.

## Native AVF graphics assessment

`NATIVE_AVF_SCANOUT = BLOCKED_BY_SPECIFIC_PERMISSION`, not absent. Samsung's
privileged Terminal uses `IVirtualizationServiceInternal.waitDisplayService()`
and `ICrosvmAndroidDisplayService.setSurface/removeSurface`; the custom app is
`untrusted_app`, has ordinary AVF VM permissions, but cannot discover that
Binder service. Generated AIDL stubs or an app-only permission request cannot
change the SELinux/service-manager decision. A platform/OEM bridge would be
required, which violates the current scope.

The viable parallel architecture remains a WinPE-side relay using production
ARM64 `viogpudo` and `viosock`, public AVF vsock, and an app-owned Surface. The
packages are verified offline but have not been runtime-bound because WinPE
userland itself is unconfirmed.

## All graphics paths and ranking

| Path | Availability | Exact blocker or proof | Reuse after EBS | Rank |
|---|---|---|---|---:|
| Samsung Terminal native display Binder | Blocked for custom app | `virtualizationservice` lookup denied to `untrusted_app`; Terminal is privileged/platform-signed | Yes, if OEM bridge exists | 5 |
| `DisplayConfig`/`GpuConfig` with ordinary app Surface | Blocked | Config causes crosvm `--android-display-service`, but no public Surface handoff is returned | Yes | 6 |
| Guest virtio-GPU resource/dma-buf export | Blocked | Export remains inside crosvm/gfxstream; no app-visible FD/resource API | No | 7 |
| Firmware GOP -> Android via console output frame | **Available in principle** | Existing raw `getConsoleOutput()` pipe is app-readable; requires new firmware encoder and app decoder | No; ends at EBS | **1** |
| Firmware GOP -> public vsock relay | Conditional | AVF `connectVsock()` is public, but EDK2 currently has no virtio-vsock producer | No; requires firmware worker before EBS | 2 |
| WinPE `viogpudo` -> `viosock` -> app Surface | Viable architecture | Production packages are verified; WinPE userland/PnP is not yet proven | Yes, through Setup/Desktop | **3** |
| File-backed framebuffer/shared RAM | Blocked | No normal-app guest RAM mapping or shared-memory export | Unclear | 8 |
| Hidden service vCPU / runtime firmware worker | Not viable short path | AVF topology and EBS ownership make it a new platform subsystem | Theoretically | 9 |

### Fastest visible-UEFI PoC

The recommended first graphics runtime is a **single pre-EBS frame over the
existing raw console output**. Firmware can read the already allocated GOP BGRA
buffer after the graphical EDK2 menu is rendered, downsample to a bounded test
mode such as 320x200, encode a fixed header plus RLE/LZ4 payload, and emit it
once on `console_out`. The app can retain the raw serial log, detect the
magic/version/length/CRC, decode into an Android `Bitmap`, and show it in an
app-owned `SurfaceView`.

This proves `FIRMWARE_FRAME_EXPORT` and `HOST_SURFACE_RENDER` without Windows,
native AVF Binder access, root, system changes, or signed Windows changes. It
does not claim continuous scanout, input, or post-EBS operation. The first
implementation must be bounded and transactional: one frame, hard payload
limit, CRC, timeout, and no changes to the immutable Windows image.

The next runtime experiment is one firmware/app pair on a throwaway VM name,
with the existing baseline Windows disk and rollback to the known firmware
asset. Expected observables are `FRAME_HEADER`, valid CRC, and a nonblank
Android bitmap. A failed pipe/throughput result closes this fallback quickly
and justifies moving to the more complex pre-EBS vsock relay.

## Keep closed

Keep closed: generic crosvm `--bios`; generic QEMU EDK2; PCI/CAM and virtio
ordering; GOP/GMM and EBS implementation; RAM-base and SMBIOS theories; SMP,
PSCI, vmwdt, BCD serial guessing; host gdbstub; direct guest-RAM mmap;
production-driver patching; and graphics/vsock PnP runtime tests before a new
Windows-side observable boundary.

## Milestones

| Milestone | Status |
|---|---|
| AVF / GenieZone, kernel-first, U-Boot, EDK2 | PASS |
| PCI root bridge/enumeration, virtio-blk/gpu | PASS |
| BOOTAA64 / Boot Manager / boot.wim load | PASS |
| ExitBootServices post-return (`ER`) | PASS |
| Modified-WIM transport and rollback | PASS |
| Kernel phase 0/1, SYSTEM consumption | UNKNOWN |
| BOOT_START acceptance/load | UNKNOWN / CI-inconclusive |
| SMSS `BootExecute` | NOT_CONFIRMED |
| `startnet.cmd`, `wpeinit`, WinPE userland | NOT_CONFIRMED |
| Native AVF scanout | BLOCKED_BY_SPECIFIC_PERMISSION |
| AVF serial duplex / KD handshake | BLOCKED / NOT_TESTED |

## Sources

Primary local evidence is retained in `STATE.md`, `CHECKLIST.md`,
`WINPE_STARTNET_REBOOT_ONLY_RUNTIME_2026-09-05.md`,
`SMSS_BOOTEXECUTE_RUNTIME_2026-09-05.md`,
`EARLY_WINDOWS_OBSERVABILITY_RESEARCH_2026-09-05.md`,
`KD_TRANSPORT_FEASIBILITY_2026-09-05.md`, and
`NATIVE_AVF_DISPLAY_AUDIT_2026-09-05.md`. No media or device state was changed
for this pass.

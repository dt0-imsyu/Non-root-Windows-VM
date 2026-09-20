# WinAVF state — 2026-09-20

## Ubuntu post-EBS Device-Tree control — 2026-09-20

V11 is the first app-owned AVF/GenieZone runtime to prove the complete Linux
kernel-to-PID-1 path using the normal FDT handoff selected during DXE:

```text
LINUX_KERNEL_POST_EBS          = PASS
LINUX_FDT_DXE_HANDOFF          = PASS
LINUX_PCI_VIRTIO_BLOCK         = PASS
LINUX_SYSTEMD_PID1             = PASS
LINUX_VIRTIO_GPU_BOUND         = PASS
UBUNTU_CASPER_BOTTOM            = PASS
UBUNTU_GNOME_DISPLAY_MANAGER    = PASS
UBUNTU_GNOME_USER_SESSION       = PASS
UBUNTU_GNOME_SCREEN_IN_APP      = NOT_AVAILABLE
```

V12 added an exact SHA-256 gate for the app-private backing-file copy and
passed it. Casper completed; `gdm.service` and live Ubuntu user sessions
started. Later SquashFS XZ errors occur while the desktop accesses more live
packages, but they do not erase the kernel-to-GNOME milestone. No post-EBS
frame relay exists yet, so the graphical session is proven on serial rather
than claimed visible in the app. Full evidence:
`docs/UBUNTU_GNOME_FDT_DXE_HANDOFF_V11_RUNTIME_2026-09-20.md`.

## Ubuntu GNOME FDT fallback boundary — 2026-09-20

The V10 standalone EFI launcher successfully mutated the EDK2-visible
`FdtClient` CPU node (`UF0`), removed ACPI (`UA0`), and reached Ubuntu
`start_kernel()` after `ER`, where Linux reported `Failed to find device node
for boot cpu` and panicked during early memory-zone initialization. A source
audit corrected the initial interpretation: KvmTool had selected ACPI during
DXE, so `FdtClientDxe` never published its HOB FDT via `gFdtTableGuid`; late
ACPI removal cannot activate that normal Device-Tree handoff.

```text
LINUX_KERNEL_POST_EBS              = PASS
LINUX_FDT_FALLBACK_ENTERED          = PASS
LINUX_FDT_BOOT_CPU_TOPOLOGY_VALID   = FAIL
UBUNTU_GNOME_LIVE_USERSPACE         = NOT_REACHED
```

The ACPI route has the complementary limitation: it reaches Casper but lacks a
usable PCI/virtio block path. Do not iterate ISO/EFI-launcher variants. The
next exact experiment is a firmware-only DXE Device-Tree-handoff A/B; only if
it fails is a lower-level U-Boot/crosvm FDT repair or a complete ACPI PCI-root
description required. Evidence:
`docs/UBUNTU_GNOME_FDT_FALLBACK_RUNTIME_2026-09-20.md`.

## Product UEFI serial-input boundary — 2026-09-14

The final r10/r11 app-owned product experiment closes the proposed serial
input route for now.  `getConsoleInput()` is available and accepts writes; an
earlier disposable byte-loopback control is byte exact.  But on the actual
Windows product topology, 220 flushed ESC bytes spanning r11's exact 30-second
EDK2 `SimpleTextIn` polling window produced no firmware acknowledgement and no
extra GOP response frame.  The original external image was rolled back and
verified exactly after the run.

```text
APP_OWNED_CONSOLE_INPUT_WRITE       = PASS
PRODUCT_TTYS0_TO_EDK2_SIMPLETEXTIN  = NOT_CONFIRMED
AVF_UEFI_SERIAL_INPUT_TRANSPORT     = BLOCKED_ON_PRODUCT_TOPOLOGY
GRAPHICAL_UEFI_INPUT                = NOT_CONFIRMED
```

Do not present serial arrow/Enter control as a product feature.  The existing
pre-EBS GOP renderer remains valid; an app Stop action can be built separately
from guest input.  Full evidence:
`docs/UEFI_SERIAL_INPUT_R10_R11_RUNTIME_2026-09-14.md`.

## Remaining post-EBS options — 2026-09-14

The independent API, trace, QEMU-contract and synthetic-platform audits now
establish the following operational boundary:

```text
LOCAL_NO_ROOT_WINDOWS_POST_EBS_ROOT_CAUSE_PATH = EXHAUSTED
PRODUCT_DEVELOPMENT_PATH                       = ACTIVE
```

No further BCD/KD/ftrace/GDB/WIM/ACPI/CPU-mask variation is justified without
a new supported platform capability. The correct next diagnostic owner is the
Samsung/GenieZone firmware path; the submitted physical-timer report requests
a vCPU timer repair or a supported trace/debug channel. A firmware/OTA
regression control and a second-device AVF control remain valid future tests.
Evidence and strict branch closure are in
`docs/REMAINING_POST_EBS_OPTIONS_2026-09-14.md`.

## QEMU accepted-platform contract — 2026-09-14

The one diskless QEMU v5 capture completed with `exit 0`, checksum-valid
FADT/MADT/GTDT/SPCR/DBG2/PPTT/IORT/MCFG records, 37 EFI memory descriptors,
and `QCP_DONE`.  It closes the last missing QEMU ACPI/EFI-map evidence.

```text
QEMU_ACCEPTED_PLATFORM_CONTRACT_CAPTURE = PASS
QEMU_AVF_WINDOWS_CONTRACT_DIFFERENTIAL  = NO_ACTIONABLE_FIRMWARE_DELTA
STOCK_LOCAL_FIRMWARE_REPAIR_CANDIDATE   = NONE
```

The QEMU↔product differences (SMC/HVC PSCI, PL011/16550 UART, timer flags,
GIC/ITS topology, RAM placement, and CPU feature profile) either truthfully
describe distinct backing machines, are optional/later facilities, or cannot
be changed without violating the product contract.  In particular, clearing
the product Low-Power-S0 FADT bit to match QEMU is invalid for the
hardware-reduced product platform; rewriting GTDT flags would also lie about
the live FDT interrupt model.  No new product VM was run.  Evidence:
`docs/QEMU_ACCEPTED_PLATFORM_CONTRACT_V5_2026-09-14.md`.

## P7 CPU contract and AVF architecture boundary — 2026-09-14

P7 captured the real product architectural CPU profile and rolled back its
single firmware range exactly. Product runs at EL1 with `MIDR=410FD851`,
`PFR0=1201011023111111`, and 13 MHz `CNTFRQ`; the working QEMU reference uses
the explicit Cortex-A76 model, a distinct feature profile, and 62.5 MHz.
Exact Windows binaries consume ID registers, but their known EL2 field test is
satisfied by both profiles. No product-only bit is tied to the silent Windows
branch, so a feature mask is not a valid local A/B.

```text
P7_RESULT            = PASS
CPU_FEATURE_CONTRACT = INCONCLUSIVE
```

The AVF architecture audit closes speculative hybrid-VMM options on stock
Samsung: private crosvm owns GenieZone VM/vCPU/RAM/exits/IRQ state, while the
app receives Binder lifecycle control plus disk, console and vsock channels.
Only virtio-fs is source-mapped to vhost-user; generic external GPU/HID/block/
net/vsock backends are not exposed. Mouse/touch APIs exist but are not yet
guest-runtime proven; keyboard injection is absent.

```text
CROSVM_EXTERNAL_DEVICE_SURFACE = FS_ONLY_PUBLICLY_EVIDENCED
GZVM_VM_HANDLE_ACCESS           = AVAILABLE_ONLY_INSIDE_CROSVM
QEMU_GZVM_ACCELERATOR            = BLOCKED_ON_STOCK_DEVICE
```

The next diagnostic action is a diskless QEMU contract capture, not another
Windows boot. Evidence: `docs/P7_CPU_ID_DIFFERENTIAL_2026-09-14.md`,
`docs/CROSVM_EXTENSION_SURFACE_AUDIT_2026-09-14.md`,
`docs/AVF_GZVM_HANDLE_OWNERSHIP_AUDIT_2026-09-14.md`, and
`docs/WINAVF_HYBRID_VMM_ARCHITECTURE_2026-09-14.md`.

## Synthetic P2.1 physical-timer boundary — 2026-09-12

The robust P2.1 retry is now valid.  A fresh physical-P2 source replay first
reproduced `BES -> P0 -> P1 -> TX` on the tablet and rolled back exactly.
Read-only FV comparison showed equal inner-FV module layout; `ConSplitterDxe`
differs by only eight DEBUG/LTO metadata bytes, so the former early abort did
not invalidate the retry.

P2.1 then reached:

```text
BES -> P0 -> P1 -> PW -> PN
```

`PW` proves the already-established virtual PPI27 watchdog woke the vCPU.
`PN` proves that after that five-second interval `CNTP_CTL_EL0.ISTATUS` was
still clear.  PPI30's handler marker (`P2`) was absent.  This is a timer
pending/emulation failure, not merely an unobserved first WFI wake.

P3 separated the remaining physical-timer states in the same bounded post-EBS
path. `PD` confirms the enabled, unmasked `CNTP_CTL_EL0` write was read back;
`PC` confirms `CNTPCT_EL0` advanced during the virtual watchdog; `PN` remains
the failed physical-comparator result. Thus the counter itself works while its
non-secure EL1 physical comparator never becomes pending.

P4 then removed the final ambiguity of the relative `CNTP_TVAL` programming
path.  It wrote an absolute `CNTP_CVAL_EL0 = CNTPCT_EL0 + 10,000,000` and
immediately got `CX` on readback; after the virtual watchdog it got `RX`,
`CE`, and `PN`.  Thus the counter passed the intended deadline, but the guest
physical CVAL state never retained the write and ISTATUS remained clear.

P5 proves only the masked pre-EBS CVAL access condition.  Before EBS, the
firmware app saved CVAL/CTL, masked the timer, wrote
`CNTP_CVAL_EL0 = CNTPCT + 10M`, and read back the exact value (`BC`); it then
restored both registers.  In the same run P4's enabled/unmasked post-EBS path
emitted `CX -> P0 -> P1 -> PW -> PC -> RX -> CE -> PN`.  This rejects universal
CNTP CVAL inaccessibility, but is not a strict EBS-causality proof because the
pre-EBS check did not enable CNTP.  A separate pre-EBS enabled control would
be needed for that vendor-only distinction.

P6 validates the P5 execution context without adding another timer mutation.
The direct raw-UART records were `L1` before EBS and `M1` after it; the EL2
VHE records are absent by design at EL1. The same run then reproduced
`PD -> CX -> P0 -> P1 -> PW -> PC -> RX -> CE -> PN`. Thus the P2–P5
accessors used the ordinary EL1 `CNTP_*` system-register path on both sides of
EBS; a switch to an EL2/VHE alias cannot explain the P5 discrepancy.

P7 independently proved the next EL1 execution primitive without touching the
timer, GIC, MMU, Windows media, or ACPI.  After the established `BES` marker,
the probe emitted `X0 -> XV`: it temporarily installed its own 2 KiB-aligned
`VBAR_EL1`, took one synchronous `BRK #0x714`, advanced `ELR_EL1` in the
handler, returned through `ERET`, restored the original vector base, and
continued.  The following `T0 -> T1 -> T2 -> T3 -> TR` records show the
existing virtual-timer/GIC/reset control path also remained intact.

```text
POST_EBS_VIRTUAL_TIMER_PPI27       = PASS
POST_EBS_CNTP_WATCHDOG_WAKE        = PASS
POST_EBS_CNTP_PENDING              = FAIL
POST_EBS_PHYSICAL_TIMER_PPI30      = FAIL
POST_EBS_CNTP_CONTROL_READBACK      = PASS
POST_EBS_CNTP_COUNTER_PROGRESS      = PASS
POST_EBS_CNTP_COMPARATOR_PENDING    = FAIL
PHYSICAL_TIMER_COMPARATOR_PATH      = FAIL
POST_EBS_CNTP_CVAL_WRITE_READBACK    = FAIL
POST_EBS_CNTP_COUNTER_PAST_CVAL      = PASS
PHYSICAL_TIMER_REGISTER_STATE        = FAIL
PRE_EBS_MASKED_CNTP_CVAL_READBACK     = PASS
PRE_EBS_CNTP_ENABLED_SEQUENCE         = NOT_TESTED
P5_RUNTIME_PROBE_VALID               = PASS
POST_EBS_EXCEPTION_LEVEL_CONTEXT     = PASS (EL1 -> EL1)
POST_EBS_EL1_EXCEPTION_VECTOR        = PASS
POST_EBS_EL1_SYNC_EXCEPTION          = PASS
POST_EBS_EL1_ERET_RETURN             = PASS
P5_CONTEXT_ALIAS_EXPLANATION         = REFUTED
P2_1_RUNTIME_PROBE_ENTRY           = PASS
WINDOWS_PHYSICAL_TIMER_DIRECT_CAUSE = REFUTED_FOR_CURRENT_WINPE_BUILD
WINDOWS_ARM64_VIRTUAL_TIMER_CODE_PATH = PASS (static)
```

The matching cross-OS timer contract is now explicit. P1 proved a real
post-EBS `CNTV_TVAL_EL0 -> virtual PPI27 -> WFI wake` path; Linux logged the
same timer as `(virt)` at 13 MHz; and the exact Windows kernel contains the
virtual comparator/control writes. This does not say Windows reached those
instructions, but it establishes:

```text
WINDOWS_LINUX_VIRTUAL_TIMER_CONTRACT = PASS
```

Evidence: `docs/WINDOWS_LINUX_VIRTUAL_TIMER_CONTRACT_2026-09-13.md`.

The immutable Android image was rehashed before apply and after rollback to
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.
Windows media, BCD, drivers, Android code, ACPI tables and VM topology were
unchanged.  Evidence:
`docs/SYNTHETIC_POST_EBS_P2_1_RETRY_RUNTIME_2026-09-12.md`.
P3 evidence: `docs/SYNTHETIC_POST_EBS_P3_PHYSICAL_COUNTER_RUNTIME_2026-09-12.md`.
P4 evidence: `docs/SYNTHETIC_POST_EBS_P4_PHYSICAL_CVAL_RUNTIME_2026-09-12.md`.
P5 evidence: `docs/SYNTHETIC_POST_EBS_P5_PRE_EBS_CVAL_RUNTIME_2026-09-13.md`.
P6 evidence: `docs/SYNTHETIC_POST_EBS_P6_EXCEPTION_LEVEL_CONTEXT_RUNTIME_2026-09-13.md`.
P7 evidence: `docs/SYNTHETIC_POST_EBS_P7_EL1_VECTOR_RUNTIME_2026-09-13.md`.

## Product WinPE 25H2 source match — 2026-09-13

The official local ARM64 25H2 ISO was read-only mounted and contains the
exact immutable baseline Windows Setup boot chain: `boot.wim`
`A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4`,
`BOOTAA64.EFI` `EFCC88441775A1ECEF644E05A52D7A01DC98388EA4426F133B9132CBE1483A19`,
and BCD `B90EF16B94C3DDA7D76CC39840BEFAA9786887517445C3B6F47EBC806D0AB105`.
Index 2 is ARM64 WindowsPE build `26100.6584`.

```text
PRODUCT_WINPE_25H2_SOURCE_MATCH = PASS
```

The product is already running this official current WinPE payload. Another
Setup-WIM replacement from this ISO would be a byte-identical no-op, so it
cannot advance `WINDOWS_POST_EBS` or `WINPE`. No VM or product image changed.
Evidence: `docs/PRODUCT_WINPE_25H2_SOURCE_MATCH_2026-09-13.md`.

## QEMU ↔ WinAVF platform differential audit — 2026-09-13

The preserved Termux/QEMU Windows control is now treated as a diagnostic
reference, not merely a fallback installer. Its launch contract explicitly
uses `-cpu cortex-a76` and `virtualization=on`; the AVF public API exposes only
one-vCPU or host-topology selection and no CPU model/feature mask. Product
Linux reports a materially newer exposed feature surface, including ECV and
E0PD. This is the one remaining early Windows-relevant platform difference,
but it is not causal proof and cannot be locally A/B tested through a safe
firmware or Windows-media change.

```text
QEMU_AVF_DIFFERENTIAL_AUDIT             = PARTIAL
QEMU_AVF_CPU_FEATURE_PROFILE_DIFFERENCE = CONFIRMED
QEMU_AVF_EL2_EXPOSURE_DIFFERENCE         = CONFIRMED_IN_QEMU / UNKNOWN_IN_PRODUCT_ID_REGS
```

The next evidence-producing action is a diskless QEMU contract capture of
ACPI/EFI-map/CPU ID registers, not another product Windows run. Evidence:
`docs/QEMU_AVF_WINDOWS_PLATFORM_DIFFERENTIAL_AUDIT_2026-09-13.md`.

## GICv3 post-EBS handoff static audit — 2026-09-13

The current ArmGicDxe driver intentionally disables its registered interrupt
sources, CPU interface and distributor in its EBS event. P1 demonstrates that
the product platform can re-arm Group-1 delivery and virtual PPI27 after that
teardown. Read-only disassembly of the exact WinPE kernel shows Windows owns a
full GICv3 initialization path (`ICC_SRE_EL1`, `ICC_PMR_EL1`,
`ICC_BPR1_EL1`, `ICC_IGRPEN1_EL1`). There is no evidence-based reason to
retain firmware GIC state for the OS.

```text
EDK2_GICV3_EBS_QUIESCENCE          = EXPECTED
POST_EBS_GICV3_REARM_PLATFORM_PATH = PASS
WINDOWS_GICV3_REINIT_CODE_PATH     = PASS (static)
FIRMWARE_GIC_HANDOFF_DEFECT         = NO_CONCRETE_DEFECT_FOUND
```

No VM ran. Evidence: `docs/GICV3_POST_EBS_HANDOFF_STATIC_AUDIT_2026-09-13.md`.

## EL1 translation handoff static audit — 2026-09-13

The exact WinPE `winload.efi` and `ntoskrnl.exe` directly install their own
EL1 translation and exception state (`TTBR0/1`, `TCR`, `MAIR`, `SCTLR`,
`VBAR`, and DAIF control). Existing EDK2 `ArmConfigureMmu()` is not usable as
a post-EBS probe because it writes live TCR and allocates via Boot Services;
a valid replacement probe would be a new MMU subsystem. No firmware table
handoff change is justified.

```text
WINDOWS_EL1_TRANSLATION_OWNERSHIP_CODE = PASS (static)
FIRMWARE_STALE_TRANSLATION_DIRECT_FIX  = NOT_SUPPORTED_BY_EVIDENCE
POST_EBS_MMU_SWITCH_PROBE_USING_EDK2   = NOT_MINIMAL
```

No VM ran. Evidence: `docs/EL1_TRANSLATION_HANDOFF_STATIC_AUDIT_2026-09-13.md`.

## Windows HVC/PSCI/IORT static audit — 2026-09-13

The residual platform-description branch is now closed without another VM
run. The exact product XSDT has FACP, GTDT, MADT, SPCR, three SSDTs and DBG2;
it has no IORT or MCFG. This is expected for the current FDT topology: the
Kvmtool configuration manager removes MCFG, PCI SSDT and IORT together when
the dynamic FDT repository has no PCI config-space object. IORT/MCFG cannot be
a Windows consumer-side cause when neither table is installed.

The same actual FDT says PSCI `method=hvc`, and FADT `armboot=0x0003` reports
the matching PSCI/HVC flags. The direct Linux ACPI control used that contract
to userland. Exact Windows `winload.efi` and `ntoskrnl.exe` contain standard
generic HVC/SMC and PSCI support wrappers, but static presence does not expose
the runtime branch and is not a defect.

```text
PRODUCT_IORT_MCFG_BOOT_CONTRACT   = NOT_APPLICABLE
PRODUCT_PSCI_HVC_CONTRACT         = PASS
LINUX_ACPI_PSCI_HVC_RUNTIME       = PASS
WINDOWS_HVC_RUNTIME_BRANCH        = UNKNOWN
HVC_PSCI_AS_CONCRETE_WINDOWS_CAUSE = NOT_PROVEN
VALID_HVC_OR_IORT_FIRMWARE_A_B    = NOT_IDENTIFIED
```

Do not invent IORT/MCFG or alter the PSCI conduit. No Windows media, BCD,
firmware, Android code, ACPI table or tablet image was modified. Evidence:
`docs/WINDOWS_HVC_PSCI_IORT_STATIC_AUDIT_2026-09-13.md`.

The GTDT audit still vetoes random one-field workarounds: the non-secure EL1
physical GSIV is not an optional availability signal and `Always-on` does not
redirect it. Stock AVF exposes no architectural-timer configuration and the
relevant GZVM tracing is privileged. The later exact-Windows instruction audit
has closed physical PPI30 as the direct cause, so do not repeat P2–P6 or make
arbitrary ACPI changes.

## Public GenieZone timer-interface audit — 2026-09-13

Public MediaTek/Android GZVM source now identifies the host-to-EL2 boundary
precisely. `GZVM_SET_ONE_REG` forwards a guest system-register write as
`MT_HVC_GZVM_SET_ONE_REG`, while the public GZVM vCPU ioctl intentionally
returns `-EOPNOTSUPP` for `GZVM_GET_ONE_REG`. The public driver has explicit
virtual-timer machinery but no public `CNTP_CVAL_EL0` retention/comparator
implementation. Therefore P4's guest-visible CVAL failure is beyond crosvm
and the public driver: its concrete owner is the closed GenieZone EL2 vCPU
timer context. No non-root local repair interface exists.

```text
PUBLIC_GZVM_TIMER_OWNER_PATH     = PASS
GUEST_CNTP_CVAL_EL2_WRITE_PATH   = IDENTIFIED
LOCAL_GZVM_CNTP_CVAL_REPAIR      = NOT_EXPOSED
```

Evidence: `docs/GENIEZONE_PUBLIC_TIMER_INTERFACE_AUDIT_2026-09-13.md`.

Read-only device and public-source audit following P3 strengthens the owner
boundary, but not the Windows causal claim.  The shipping tablet has live
`gzvm` and `timer_mediatek` modules, exposes no architectural-timer control or
trace endpoint to a normal user, and the public GenieZone implementation
documents vtimer migration/maintenance without an equivalent physical-timer
path.  The only responsible layer left after P3's guest-side proof is
GenieZone EL2/GZVM timer context, but the proprietary EL2 implementation is
not inspectable here.  See
`docs/GENIEZONE_P3_PHYSICAL_TIMER_OWNER_EVIDENCE_2026-09-12.md`.

## ARM Generic Timer platform contract — 2026-09-12

P2.1 now establishes a platform-level failure independently of Windows: the
product VM advertises the non-secure EL1 physical timer (`CNTP_*`, PPI30) in
the same FDT→GTDT path it gives its guest, yet a five-second virtual PPI27
watchdog fires while `CNTP_CTL_EL0.ISTATUS` remains clear.  The physical timer
does not even become pending, so this is not merely an unobserved GIC interrupt
or `WFI` wake.

```text
ARM_GENERIC_TIMER_PLATFORM_CONTRACT = FAIL
WINDOWS_BLOCKER_PHYSICAL_TIMER      = STRONG_HYPOTHESIS
WINDOWS_EARLY_TIMER_SELECTION       = UNKNOWN
VALID_WINDOWS_TIMER_SELECTION_A_B   = NOT_IDENTIFIED
```

Linux's successful post-EBS path used `CNTV`/PPI27, so it neither proves nor
disproves Windows' use of PPI30.  Microsoft documents GTDT-backed Arm Generic
Timer support but does not publish Windows ARM64's early HAL selection logic.
The result forbids an arbitrary GTDT rewrite: PPI remapping would make the
description false rather than redirect `CNTP_*`.  See
`docs/ARM_GENERIC_TIMER_PLATFORM_CONTRACT_2026-09-12.md`.

## Windows ARM64 timer instruction audit — 2026-09-13

The prior Windows causal inference is now closed for the exact WinPE kernel in
the product baseline.  Read-only extraction and ARM64 disassembly of
`Windows 11 26100.6584` from the unmodified baseline WIM found two guest
virtual-comparator writes (`MSR CNTV_CVAL_EL0`) and one virtual-control write
(`MSR CNTV_CTL_EL0`) in `ntoskrnl.exe`, with **zero** writes to
`CNTP_CVAL_EL0`, `CNTP_CTL_EL0`, or `CNTP_TVAL_EL0`.  The extracted
`winload.efi` and `hal.dll` also have zero physical-comparator writes.

The kernel does read `CNTPCT_EL0` in a small number of paths, but a counter
read cannot arm the failed physical comparator.  Therefore P2–P5 are a real
GenieZone platform-contract failure but not a direct explanation of this
WinPE's post-EBS stall via `CNTP_*` comparator programming.

```text
WINDOWS_ARM64_VIRTUAL_TIMER_CODE_PATH = PASS (static)
WINDOWS_PHYSICAL_TIMER_DIRECT_CAUSE   = REFUTED_FOR_CURRENT_WINPE_BUILD
ARM_GENERIC_TIMER_PLATFORM_CONTRACT   = FAIL (independent platform defect)
```

No VM ran, and no media, BCD, firmware, Android app or baseline byte changed.
Evidence: `docs/WINDOWS_ARM64_TIMER_INSTRUCTION_AUDIT_2026-09-13.md`.

## Linux ACPI-only product control — 2026-09-11

One bounded independent Debian ARM64 control ran on the exact product
AVF/GenieZone topology. It used EDK2 → Debian GRUB → Debian kernel with
`acpi=force`, the known `ttyS0`, and explicit 16550 earlycon; Windows BCD and
WIM were untouched. Offline FAT, ARM64 PE, GRUB command line, and source asset
checks passed.

EDK2 successfully started Debian `BOOTAA64.EFI` and emitted the established
raw post-EBS `ER` boundary. Serial stayed silent for the full 100-second capture:
no GRUB/Linux/ACPI/earlycon record occurred. This is not a direct kernel-PC
observer, so kernel entry remains unknown; it does invalidate treating the
silence as proven WinPE/Setup-only. The 24-range overlay was rolled back and
the Android external baseline rehashed exact.

```text
LINUX_ACPI_ONLY_CANDIDATE      = PASS
LINUX_ACPI_ONLY_RUNTIME        = NOT_CONFIRMED
LINUX_KERNEL_EARLY_SERIAL      = NOT_OBSERVED
COMMON_POST_EBS_SERIAL_SILENCE = OBSERVED
PRODUCT_BASELINE_RESTORED      = PASS
```

Evidence: `docs/LINUX_ACPI_ONLY_RUNTIME_2026-09-11.md`.

## Linux direct EFI-stub v3 earlycon correction — prepared 2026-09-11

The v2 direct EFI-stub run reached the Linux stub's own successful
ExitBootServices return but printed no native Linux line.  A focused static
comparison found that the v2 option selected 32-bit `uart8250,mmio32`, while
the actual EDK2 serial implementation uses 8-bit MMIO registers at `0x3f8`
with stride 1.  The direct launcher was rebuilt as a module only with the
sole option change to `earlycon=uart8250,mmio,0x3f8`; no FD, Windows media,
Android app, or tablet image changed.

```text
LINUX_EARLYCON_ACCESSOR_CONTRACT = MISMATCH_CONFIRMED
LINUX_EFI_STUB_V3_LAUNCHER_BUILD = PASS
LINUX_EFI_STUB_V3_OFFLINE_MEDIA  = PASS
LINUX_EFI_STUB_V3_RUNTIME        = PASS
LINUX_NATIVE_KERNEL_POST_EBS     = PASS
LINUX_USERSPACE_INSTALLER        = PASS
POST_EBS_PLATFORM_FOR_LINUX      = PASS
```

The new launcher is `20,480` bytes, ARM64 PE, SHA-256
`F3FEE2904150D53D309D220D3BF4D0F7597B81B63964A496DAB0A51D8B5C1DEE`.
Its isolated preparation entry point is
`tools/linux-efi-stub-control/prepare-linux-efi-stub-control-v3-mmio8.ps1`.
The one-run evidence and exact rollback proof are in
`docs/LINUX_EFI_STUB_V3_MMIO8_RUNTIME_2026-09-11.md`.

## Product KD gated control and next-session handoff — 2026-09-09

The app-owned bridge is proven binary-transparent end-to-end at `ttyS0/0x3f8`.
The first product KD run was deliberately invalidated by a real preboot serial
collision: KD sync bytes interrupted U-Boot.  A second, gated control withheld
all KD process creation and host TX until `Loading files...`; that text is not
visible on the product raw UART, so KD was never released.  The control still
reached the late `IMAGE_AUDIT start enter` pre-EBS marker and stopped only five
bytes before historical r11 `BES` due the host gate timeout.  It is not an EBS
or KD failure.

```text
APP_OWNED_BINARY_TRANSPARENT_COM1 = PASS
GATED_NO_PREBOOT_KD_TX            = PASS
LOADING_FILES_UART_MARKER         = NOT_OBSERVED
WINDOWS_KD_HANDSHAKE              = NOT_TESTED_BY_GATED_RUN
PRODUCT_BASELINE_RESTORED         = PASS
```

The live Android external image and the private runtime after rollback both
hash exactly to `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`;
there are no running VMs and `hidden_api_policy=null`.  The only proposed
future run, requiring fresh authorization, uses the existing BCD+r11 combined
patch `4F2EA0...B93742E6` and gates KD on the real raw marker
`IMAGE_AUDIT start enter`.  Never start KD before that marker and never retry
the invisible `Loading files...` gate.  Full handoff, commands, build
environment, recovery sequence, and artifact map:
`docs/NEXT_SESSION_HANDOFF_PRODUCT_KD_2026-09-09.md`.

### `IMAGE_AUDIT` gate control update

One later authorized control proved `IMAGE_AUDIT start enter` is a real,
observable post-U-Boot serial gate.  The host bridge then failed locally at an
invalid `.NET NetworkStream.ReadTimeout=0` assignment before it created
`kd.exe` or transmitted any debugger byte.  The bridge now uses
`System.Threading.Timeout.Infinite`; no repeat was made.  Transactional
rollback, external baseline SHA, no-running-VM state, and hidden policy
restoration all pass.

```text
IMAGE_AUDIT_GATE_OBSERVED = PASS
GATED_NO_PREBOOT_KD_TX    = PASS
WINDOWS_KD_HANDSHAKE      = NOT_TESTED
```

Evidence: `docs/PRODUCT_APP_OWNED_KD_IMAGE_AUDIT_GATE_RUNTIME_2026-09-09.md`.

### Bridge readiness control update

The subsequent host invocation ended before Android token authentication: the
one-shot app listener had only just written `state=LISTENING` when the host
attempted its connection.  No VM was created and no private-image patch was
active.  The host bridge now waits for that durable readiness record before it
makes its one client connection.  Baseline/no-VM/policy checks remain exact.
Evidence: `docs/PRODUCT_APP_OWNED_KD_BRIDGE_READINESS_CONTROL_2026-09-09.md`.

### Product KD at the real image-audit gate

The repaired bridge has now had its one product runtime.  It observed the real
`IMAGE_AUDIT start enter` marker, then safely opened KD and sent 450 raw KD
bytes after U-Boot.  `kd.exe` received no target packet; raw output contained
no complete `BES` and stopped after the final two `CONVERT_AUDIT` lines.
Rollback and baseline verification passed.  This is a valid negative KD
handshake result, not a reason to vary BCD or firmware blindly.

```text
IMAGE_AUDIT_GATE_OBSERVED      = PASS
GATED_NO_PREBOOT_KD_TX         = PASS
WINDOWS_KD_HANDSHAKE           = NOT_OBSERVED
EXIT_BOOT_SERVICES_THIS_KD_RUN = NOT_OBSERVED
WINDOWS_KERNEL_ENTRY           = UNKNOWN
```

Evidence and the required next read-only semantics audit:
`docs/PRODUCT_APP_OWNED_KD_IMAGE_AUDIT_RUNTIME_2026-09-09.md`.

### Product KD BCD phase-semantics audit

The read-only audit is complete. `{default}.bootdebug` and
`{default}.debug`, with inherited COM1/115200 settings, configure Winload and
kernel KD. `{bootmgr}.bootdebug` is intentionally absent, so no target reply
was required at the early EDK2 `IMAGE_AUDIT` release marker. A prior
bootmgr-enabled A/B changed Boot Manager behaviour and still had no handshake;
the BCD/KD variant branch is closed.

```text
SERIAL_KD_BCD_SETTINGS         = PASS
EXPECT_KD_REPLY_AT_IMAGE_AUDIT = NO
BCD_KD_VARIANT_BRANCH          = CLOSED
WINDOWS_KERNEL_ENTRY           = UNKNOWN
```

Evidence: `docs/PRODUCT_KD_BCD_PHASE_SEMANTICS_AUDIT_2026-09-09.md`.

## Current authoritative graphics state — 2026-09-06

The r4 host environment has now been replayed successfully and used to build
r5. `R4_BUILD_ENV_REPLAY = PASS` and `NEW_GOP_FD_BUILD = PASS`.

The r5 FD is archived as
`firmware-work/edk2/artifacts/KVMTOOL_EFI-gop-r5-diagnostic.fd` (2,097,152
bytes, SHA-256
`3EAFC9C2086ADCF0375AA14A947E482CB86BE6A1D2AAA105C974DBB2671EFF00`).
It differs from r4 only in the bounded diagnostic second GOP/WAVF capture.

One transactional, firmware-only runtime run produced two CRC-valid 320×200
WAVF records. The original sequence-1 GOP capture remains black; the r5
sequence-2 GOP diagnostic capture has B=0..255, G=0..255, R=128 and visibly
rendered in the real Android `SurfaceView`. The launcher then rolled the one
2 MiB range back and verified the immutable runtime baseline.

```text
REAL_GOP_NONBLACK_FRAME = PASS
GRAPHICAL_UEFI_VISIBLE_IN_APP = PASS
```

The authoritative runtime evidence and exact hashes are in
`docs/GOP_R5_DIAGNOSTIC_RUNTIME_2026-09-06.md`. Older sections below describe
the earlier r4 black-frame state and superseded replay blocker; they are kept
as historical evidence only.

### r6 real BDS UI capture

r6 uses the standard `BootLogoUpdateProgress()` drawing primitive and captures
the centered GOP area as WAVF sequence 3. The tablet SurfaceView visibly showed
the TianoCore logo. Its raw capture has CRC `0xC92231D9` PASS, 65 distinct
colors, and 11,194 non-black pixels; firmware separately logged successful
BDS draw and centered capture. The firmware-only patch was immediately rolled
back and verified.

```text
GOP_BDS_PROGRESS_DRAW = PASS
REAL_GOP_BDS_CENTER_CAPTURE = PASS
GRAPHICAL_UEFI_VISIBLE_IN_APP = PASS
```

See `docs/GOP_R6_BDS_CENTER_RUNTIME_2026-09-06.md`.

### r7 repeated BDS capture sequence

r7 made three standard `BootLogoUpdateProgress()` calls (0, 50, 100), each
followed by a centered GOP/WAVF capture. All progress and capture status
markers were `Success`; sequences 3, 4, and 5 arrived with CRC PASS. The
three payloads were byte-identical because the already-proven 320×200 centered
crop contains the TianoCore logo but excludes the BDS progress-bar region.
The TianoCore logo remained visibly rendered in the real Android SurfaceView.
The single one-range firmware patch was immediately rolled back and the full
immutable runtime SHA was revalidated.

```text
PRE_EBS_REPEATED_FRAME_TRANSPORT = PASS
BDS_PROGRESS_FRAME_SEQUENCE = NOT_CONFIRMED
BDS_PROGRESS_VISUAL_DELTA = NOT_CONFIRMED (center crop unchanged)
GRAPHICAL_UEFI_VISIBLE_IN_APP = PASS
```

Exact evidence and hashes: `docs/GOP_R7_BDS_PROGRESS_SEQUENCE_RUNTIME_2026-09-06.md`.

### r8 real BDS visual-delta capture

r8 changed only the BDS capture window to bottom-center, where the standard
BootLogoLib implementation draws its bar. The 0/50/100 progress draws and WAVF
sequences 3/4/5 all returned `Success` and all CRC checks passed. The three
payload SHA-256 values differ, and the real SurfaceView visibly showed the
standard `Press ESCAPE for boot options` text with the fully drawn BDS bar.
The firmware-only one-range patch was immediately rolled back and the full
immutable runtime baseline SHA was revalidated.

```text
BDS_PROGRESS_FRAME_SEQUENCE = PASS
BDS_PROGRESS_VISUAL_DELTA = PASS
GRAPHICAL_UEFI_VISIBLE_IN_APP = PASS
```

Exact evidence and hashes: `docs/GOP_R8_BDS_PROGRESS_VISUAL_DELTA_RUNTIME_2026-09-06.md`.

### Fullscreen renderer launcher UI

The installed WinAVF launcher now uses a fullscreen, edge-to-edge
`FrameSurfaceView` as its root content. The obsolete Start/Rollback/AVF-audit
buttons and scrolling serial panel were removed. The short status overlay is
automatically hidden when the first WAVF frame arrives, so the guest image is
never covered. Existing automation remains explicit-intent based:
`--ez start true`, `--ez rollback true`, and audit extras are unchanged.
The UI-only synthetic frame test showed an unobscured full-screen frame; no VM
or guest media was accessed by that test.

## Pre-EBS GOP → WAVF raw-console runtime PoC — 2026-09-06

`EXPERIMENTAL_GOP_FD_CANDIDATE = PASS`: the completed r4 FD is
`firmware-work/edk2/Build/ArmVirtKvmTool-AARCH64/DEBUG_GCC5/FV/KVMTOOL_EFI.fd`
(2,097,152 bytes, SHA-256
`8BB42784791B6618D599EF7552C2CF4DFBA61AE5E07B7F08AC76B3F01F48392C`).
The r4 build log ends in `- Done -`; its BdsDxe and FVMAIN contain the
`AVF_GOP_FRAME` marker.  Its reproducibility in the restored historical host
environment is still separate work; therefore `NEW_GOP_FD_BUILD` is not yet
claimed PASS.  See `docs/GOP_FD_CANDIDATE_AUDIT_2026-09-06.md`.

One isolated tablet run used no WIM/BCD/GPT/FAT changes.  The installed legacy
WinAVF launcher applied a one-range `WAVFPAT1` firmware bundle only to the
existing equal-size `\\EFI\\EDK2\\QEMU_EFI.fd` range at raw offset
`7250927616` (2,097,152 bytes), then its own range read-back validation
started the VM.  Before application, tablet media SHA-256 exactly matched the
immutable baseline `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.
The bundle SHA-256 was
`8A90A63D1B80F28F25DC6011878F58EA66DD1945348577D6AB9854873F2F4179`.

The retained raw console capture
`build-logs/gop-poc-20260906/runtime-r4-raw-serial.log` (266,253 bytes,
SHA-256 `B9B9C32EE188F96A22B61C8A7F71A877FE6A2D07F14503BDA4FB4384187992C2`)
contains a `WAVF` binary header at byte offset 4745 and the exact firmware
marker `AVF_GOP_FRAME status=Success size=320x200`.  This proves
`GOP_WAVF_RAW_CONSOLE_EXPORT = PASS`: GOP capture and binary output reach the
Android app's captured `console_out` pipe before EBS.

The first legacy APK had no decoder, but a controlled same-certificate update
preserved the known-good launcher contract and added the decoder/SurfaceView.
Its UI-only synthetic WAVF audit visibly rendered a gradient in the tablet
SurfaceView, so `SURFACEVIEW_PRESENTATION = PASS`.  A second one-run firmware
test had a CRC-valid 320x200 payload but all 64,000 pixels were BGRA
`00 00 00 FF`; the black SurfaceView is thus correct, and
`REAL_GOP_FRAME_VISIBILITY = BLOCKED_BY_BLACK_SOURCE_FRAME`.  After each
runtime test the launcher reported verified rollback and a separate tablet
SHA-256 check again matched the immutable baseline.  Full procedure/evidence is in
`docs/GOP_WAVF_RUNTIME_POC_2026-09-06.md`.

## r4 build forensic replay — 2026-09-06

The r4 success used `BaseTools\\Bin\\Win64`, bundled llvm-mingw Python, GCC
15.2, MSYS `mingw32-make`, `cmd.exe`, and a wrapper pair visible in its log:
`objecho.cmd` plus `iasl-msys.cmd`. All Win64 packaging binaries remain on
disk. The replay reaches IASL with the recorded environment, but the currently
saved IASL wrapper was written after r4 and loses its `-pC:\\...` path when
invoking POSIX IASL. The r4 path-preserving wrapper implementation is absent.

`R4_BUILD_ENV_REPLAY = BLOCKED_BY_MISSING_R4_IASL_WRAPPER_SEMANTICS`. No r5 FD
was built; the source-only diagnostic GOP gradient remains staged, while the
r4 FD and tablet baseline remain unchanged.

A follow-up source-only GOP diagnostic frame (gradient drawn through GOP Blt,
then restored) is staged but has **no new FD**.  The attempted controlled
historical build stopped before packaging on the known generated-make
`"echo"`/`cmd.exe` incompatibility (`EnglishDxe`, `FdtClientDxe`, `SerialDxe`,
and `CpuMmio2Dxe` fan-out).  No tablet media was changed.  Do not treat this
as a firmware regression or attempt generic build-environment repair without a
bounded exact historical-build plan.

## Terminal/VmLauncher reverse engineering — 2026-09-05

Absolute project priority is now the graphical product path. The installed
Samsung Terminal APK was inspected together with framework and crosvm source.
The exact result is `TERMINAL_DISPLAY_PATH = HARD_BLOCKED_BY_EXACT_PLATFORM_PRIVILEGE`:
`DisplayActivity` and `VmLauncherService` are non-exported, the service is not
bindable (`onBind() = null`), and display uses hidden
`IVirtualizationServiceInternal.waitDisplayService()` plus
`ICrosvmAndroidDisplayService.setSurface()`. The custom app is `untrusted_app`
and cannot find the `virtualizationservice` Binder under the device SELinux
policy. Full evidence is in
`docs/TERMINAL_VM_LAUNCHER_REVERSE_2026-09-05.md`.

`TERMINAL_DISPLAY_BRIDGE` is not reusable for an external VM and
`TERMINAL_VM_HOST` is not reusable with our disk/ISO/kernel. The normal-app
channels confirmed in source are captured `console_out`, input sockets, and
public `connectVsock()`; no Surface, dma-buf, guest-RAM, or crosvm resource
export exists in the public framework. The graphics workstream therefore moves
to a GOP-frame-over-console PoC, then a production-signed WinPE vsock relay.
Post-EBS Windows diagnostics are not the active path and should remain closed.
See the new report for the ranked implementation path.

The first frame transport is now specified and its bounded Android decoder is
implemented in `android-app/src/com/example/winavf/ConsoleFrameDecoder.java`.
It uses a 28-byte `WAVF` header, CRC32, sequence numbers, one BGRA keyframe,
and compressed/raw tile updates. Raw 1280x800 at 30 FPS would require about
117 MiB/s, so the product targets a 10 FPS installation cap and 30 FPS
interactive cap with dirty-tile updates. No firmware, Windows image, or tablet
runtime state was changed. See `docs/CONSOLE_FRAME_TRANSPORT_2026-09-05.md`.

The decoder is wired into the existing `getConsoleOutput()` reader and presents
decoded BGRA frames on the app-owned `FrameSurfaceView`. A host-side synthetic
keyframe plus tile stream passes (`ConsoleFrameDecoderSelfTest PASS frames=2`).
Firmware emission is still pending, so no claim of tablet-visible frames or
measured FPS is made yet. A one-shot firmware encoder is now present in
`firmware/PlatformBootManagerLib/PlatformBm.c`: it captures a bounded 320x200
GOP region, emits a `WAVF` keyframe with CRC over `SerialPortWrite`, and logs
`AVF_GOP_FRAME`. It is offline source work only; firmware build/runtime proof
is still pending. The actual EDK2 module source is also patched in
`firmware-work/edk2/ArmPkg/Library/PlatformBootManagerLib/PlatformBm.c`; its
generated `PlatformBm.obj` now compiles successfully with the workspace LLVM
toolchain. Full FV/FD linking was attempted with local reversible tool shims and
reached the generated FFS stage, but this checkout lacks a coherent Windows
EDK2 BaseTools set (`iasl` is Unix-only and VFR/GenSec tooling does not complete
the host rules). The existing runtime FD was not replaced and no tablet
runtime claim is made.

## Astra first pass — 2026-09-05

The current strongest proven Windows boundary remains the post-return EDK2
`ER` marker after `ExitBootServices`. Kernel phase 0/1, SYSTEM hive
consumption, BOOT_START acceptance, SMSS, `wpeinit`, `startnet.cmd`, and WinPE
userland remain unconfirmed; absent reboot/marker effects are non-diagnostic.
The standard artifact audit found no conforming phase-specific signal under the
current constraints. `BOOTSTAT.DAT` is loader-side only; `ntbtlog` is not a
durable sink in the present RAM-backed WinPE; crash/recovery side effects are
ambiguous or destructive; KD/bootdebug is the only high-resolution candidate,
but AVF lacks writable console input. Therefore no new runtime patch is
justified until duplex console capability is proven. See
`docs/ASTRA_FIRST_PASS_2026-09-05.md`.

`NATIVE_AVF_SCANOUT` remains `BLOCKED_BY_SPECIFIC_PERMISSION`: the privileged
Terminal display Binder exists, while the custom app is `untrusted_app` and
cannot discover it. The product-side viable architecture remains a WinPE
production-signed `viogpudo`/`viosock` relay over public vsock to an app-owned
Surface, but its runtime binding is blocked by the unconfirmed WinPE boundary.

Graphics priority update: crosvm's `console_out` is a raw app-readable pipe,
separate from the privileged Android display service. The fastest safe visible
UEFI candidate is a bounded single GOP frame encoded by firmware and sent
before EBS over existing console output, then decoded into an app-owned
SurfaceView. This is a pre-EBS fallback, not native scanout and not a post-EBS
relay. It is not implemented or run yet; the next PoC must use a throwaway VM
name, bounded payload/CRC, and preserve the immutable Windows baseline. Full
path ranking is in `docs/ASTRA_FIRST_PASS_2026-09-05.md`.

## Preserved boot milestones

- `EXIT_BOOT_SERVICES_RETURN = PASS`
- `MODIFIED_WIM_EBS = PASS`
- `MODIFIED_WIM_TRANSPORT = PASS`
- Immutable runtime baseline SHA-256: `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

## WinPE PnP reporter run — 2026-09-05

- `SIGNED_RAW_UART_PNP_MARKER = BLOCKED` is closed under the production-signing
  constraint.  No production-signed virtio binary was modified.
- The separate reporter WIM was an append-only copy of the preserved graphics
  candidate.  It added only a CRT-free ARM64 SetupAPI executable and replaced
  `startnet.cmd` with `wpeinit → reporter → wpeutil reboot`.
- Reporter WIM: `629584824` bytes,
  SHA-256 `8A23DE5EA981800DF089E43EB8AC42FD576CF5E2E6E102B17795B89D7436B7CD`.
  It verified with wimlib.  The executable imports only `KERNEL32.dll` and
  `SETUPAPI.dll`, both present in this WinPE image.
- Runtime patch: `12409548` bytes, `13` ranges,
  SHA-256 `2C1CE4632C131E40FC4584BB89DCAFD34C08E3BEFC28E959D500BB5177A62572`.
  Offline FAT1/FAT2, bridge, reconstructed-WIM and rollback checks all passed.
- The one permitted runtime run reached the existing serial boundary `ER`
  after Windows Boot Manager.  Neither persistent `WINPE.TXT` / exported
  userland marker nor the deterministic reboot occurred.

Result: `WINPE_USERLAND = NOT_CONFIRMED`; `WINPE_VIOGPU_BOUND`,
`WINPE_VIOGPU_STARTED`, `WINPE_VSOCK_BOUND`, and `WINPE_VSOCK_STARTED` remain
`NOT_TESTED`.  This is not evidence against either virtio driver.

The transactional patch was rolled back immediately.  The installed app's
visible status confirms: “Small image patch rolled back and the runtime image
was verified.”  See `docs/WINPE_PNP_REPORTER_RUNTIME_2026-09-05.md`.

The graphics audit made no firmware, BCD, FAT, WIM, Windows-media, or runtime-image change.

## Pre-`wpeinit` persistent-marker run — 2026-09-05

This follow-up isolated the launch ordering without changing the signed virtio
drivers or adding the PnP reporter.  It used the preserved graphics candidate
as the source WIM and changed only index 2:

```text
\WinAvf\WinAvfPreWpeinitMarker.exe
\Windows\System32\startnet.cmd = marker → wpeinit → wpeutil reboot
```

The new CRT-free ARM64 marker imports only `KERNEL32.dll`.  Before `wpeinit`,
it searches for `WINSETUP` on FAT32 (never assumes a drive letter and rejects
`X:`), then tries to write both `\WinAvf\pre-wpeinit-pass.txt` and root
`\WINPE.TXT` so the installed launcher can export the latter.

- Marker SHA-256: `B2F9CD593E5B5DBF83C1CBAC0D3CE85DF7915BE518C9437F5075201D522BCF0F`.
- WIM: `629583629` bytes,
  SHA-256 `7C305B8E031E980EA7C87550EE1D8400C71F3F45D318C0E1AE63173733CCE320`;
  `wimlib verify = PASS`.
- Transactional patch: `12407158` bytes, `13` ranges,
  SHA-256 `57FF135345304560EC0756AD8497B6E633EB25FFBB77F553EFEA516A8BBC7464`.
- Read-only audit against immutable baseline passed: `FAT1/FAT2=PASS`,
  `OldTail=82936`, `FirstNewCluster=882627`, reconstructed WIM hash matched,
  directory invariants and rollback simulation passed.

One runtime run was made after rechecking the device baseline hash.  Its
serial log (SHA-256
`BCD8318269495EDA1D29313B2252DD2F0758B6E6F8C3BDE8C2DDA24225B661D6`)
again stopped at the raw `ER` boundary; there was neither an exported
`WINPE.TXT` nor a reboot.  Exact rollback then completed and reverified the
baseline hash.

Result: `STARTNET_PRE_WPEINIT = NOT_CONFIRMED` and
`WPEINIT_COMPLETION = NOT_CONFIRMED`.  The absence of the persistent marker
does **not** prove that `startnet.cmd` was never entered: the `WINSETUP` volume
may not be mounted or writable at that moment.  It does prove only that this
persistent-volume channel did not yield an observable user-mode signal; no
conclusion about `wpeinit`, viogpu, or viosock is justified.

See `docs/WINPE_PRE_WPEINIT_MARKER_RUNTIME_2026-09-05.md`.

## `startnet.cmd → wpeutil reboot` run — 2026-09-05

This was the narrower follow-up to remove the persistent-volume ambiguity.
The exact baseline WIM was copied and index 2 changed only
`\Windows\System32\startnet.cmd` to the 16-byte payload:

```text
wpeutil reboot
```

There was no `wpeinit`, marker, reporter, driver/package, graphics/vsock,
BCD, or firmware change.

- WIM: `624978518` bytes,
  SHA-256 `48C6CD2C5E8845DE028846D9EB882C7E142D92D1948B9A0334F96477A3102D13`;
  `wimlib verify = PASS`.
- Transactional patch: `3187640` bytes, `9` ranges,
  SHA-256 `658291E9538718346F3E94443CA13C14187BF35047B200E6FAFF7403958823DC`.
- Overlay audit passed against immutable baseline: `FAT1/FAT2=PASS`,
  `OldTail=82936`, `FirstNewCluster=2679`, reconstructed WIM hash matched,
  directory invariants and rollback simulation passed.

The device baseline hash matched before staging.  Exactly one VM run was
launched.  It did not reset: crosvm remained alive and serial again stopped at
the raw `ER` boundary.  Saved serial SHA-256:
`10D134C9DB9353BE3DEE5EB90A88E66CAA12E9FA62145B41D93AADF77F8EBAE7`.

Result: `STARTNET_CMD_EXECUTION = NOT_CONFIRMED`.  This makes no claim that
the command interpreter itself cannot run; it establishes that no independent
observable `wpeutil reboot` execution occurred in this boot.  `wpeinit`, PnP,
viogpu, and viosock remain out of scope until this earlier WinPE-user-mode
startup boundary is explained.

Rollback completed immediately and the external baseline hash matched again.
See `docs/WINPE_STARTNET_REBOOT_ONLY_RUNTIME_2026-09-05.md`.

## SMSS BootExecute probe — 2026-09-05

This test moved the observation point before `startnet.cmd`/`wpeinit`.  It
added a CRT-free ARM64 **Native** executable to `\Windows\System32` whose
only import is `ntdll.dll!NtShutdownSystem(ShutdownReboot)`.

Offline SYSTEM inspection found that selected `ControlSet001` had no
`BootExecute` value.  Therefore no existing entry was replaced: a new
`REG_MULTI_SZ` was created with exactly:

```text
WinAvfSmssProbe.exe
```

The extracted target WIM contained `ntdll.dll`; the extracted SYSTEM hive was
hash-identical to the one created by the offline editor.

- Probe: `3072` bytes,
  SHA-256 `4FDC66A77A1C3C53ED21740103CED8354F1D9C6FB3854D529B22B4710C1049F1`.
- WIM: `625622678` bytes,
  SHA-256 `0BD3041AD4F5C3BDE4B7CD0B506EB8B4614EAE4F3BF3DCDA14BF617EA72B9883`;
  `wimlib verify = PASS`.
- Patch: `4477284` bytes, `10` ranges,
  SHA-256 `60F161A29B13496E993DD5DA941B79C54AAC98C82B6642680DDBD87BAE80E39A`.
- Read-only audit against the immutable baseline passed: `FAT1/FAT2=PASS`,
  `OldTail=82936`, `FirstNewCluster=882627`, reconstructed WIM hash matched,
  directory invariants and rollback simulation passed.

After device baseline verification, one VM run was launched.  `ER` was again
the last serial evidence, crosvm remained alive, and no reboot/reset occurred.
The serial SHA-256 is
`84151440EBADAB402D02B705B78916C2FD76B3B5305DBD329FEA807D12958EC8`.

Result: `SMSS_BOOTEXECUTE = NOT_CONFIRMED`.  This does **not** diagnose a
broken SMSS: a Native BootExecute executable can still be declined or not
reached for a pre-SMSS reason.  The confirmed boundary is now:

```text
ExitBootServices / ER = PASS
Windows kernel/HAL early initialization = UNKNOWN
SMSS BootExecute execution = NOT_CONFIRMED
WinPE userland = NOT_CONFIRMED
```

The transactional patch was rolled back immediately and the external baseline
hash matched again.  See `docs/SMSS_BOOTEXECUTE_RUNTIME_2026-09-05.md`.

## BOOT_START load-boundary acceptance preflight — 2026-09-05

No runtime media was built, staged, or run for this branch.  Acceptance was
examined before treating the existing `WinAvfBootProbe` as a kernel boundary
instrument.

The existing custom binary is ARM64 Native (`Type=1`, `Start=0` service plan,
`ImagePath=%SystemRoot%\System32\drivers\WinAvfBootProbe.sys`) and has a
bounded early UART `D/S` marker in `DriverEntry`.  Its SHA-256 is
`7F8E75C440048B60F0E10AFD0BF6DC0330616682A2D252C84FE3387BDE0D5B1B`.
However, it is signed only with the local self-signed certificate
`CN=WinAVF Boot-Start Diagnostic`; `signtool verify /kp` fails because that
root is untrusted.  Its INF names a catalog, but no `.cat` was produced.

The target WIM does contain Microsoft-supplied ARM64 boot-capable binaries
such as `acpi.sys`, `pci.sys`, `disk.sys`, and `Classpnp.sys`.  They have no
separately observable DriverEntry path.  Modifying any production-signed
binary to add one would invalidate its catalog member hash, which is outside
the current secure-boot/no-testsigning scope.

Result:

```text
BOOT_DRIVER_ACCEPTED = UNKNOWN
BOOT_START_PROBE = INCONCLUSIVE_DUE_TO_CI
BOOT_START_LOAD = INCONCLUSIVE
DRIVER_ENTRY = NOT_TESTED
```

No BCD or testsigning change was made.  Do not infer a kernel failure from
the absence of the old `D/S` marker.  The next boundary must be earlier than
SMSS but independently observable without an untrusted kernel component; see
`docs/BOOT_START_ACCEPTANCE_PREFLIGHT_2026-09-05.md`.

## Early Windows observability static research — 2026-09-05

No runtime artifact was created or run.  Read-only inspection of the exact
baseline WinPE found Microsoft-signed ARM64 `winload.efi`, `ntoskrnl.exe`,
`kdcom.dll`, and `kdnet_uart16550.dll`; `signtool verify /kp` passed for each.
Their presence does not solve the actual limitation: the current AVF serial
path is output-only and therefore cannot form a KD/boot-debug endpoint.

Standard paths were audited without changing BCD: KD/bootdebug, EMS,
`bootlog`/`Ntbtlog.txt`, Boot Status Data/`BOOTSTAT.DAT`, crash dumps, and a
configuration-only use of already signed boot-start drivers.  None yields an
independent, phase-specific external signal under the simultaneous constraints
of no BCD changes, no custom trusted kernel code, no signed-binary/catalog
change, and no bidirectional KD transport.

Result:

```text
EARLY_WINDOWS_OBSERVABILITY = BLOCKED
```

The blocker is transport plus policy, not WIM/FAT transport.  Do not build a
new runtime candidate in this branch.  The smallest meaningful next test, if
explicitly authorized, is a temporary BCD boot-debug setup over a genuine
bidirectional AVF console bridge, using existing Microsoft-signed components;
it still requires both currently forbidden capabilities.  See
`docs/EARLY_WINDOWS_OBSERVABILITY_RESEARCH_2026-09-05.md`.

## AVF console / KD transport audit — 2026-09-05

The actual Android 16 `VirtualMachine` runtime on `R52Y9072A2R` was queried
without running a VM.  It exposes `getConsoleOutput(): InputStream`, but no
`getConsoleInput()`, writable console FD, or equivalent Binder API.  A prior
attempt to invoke `getConsoleInput()` ended in `NoSuchMethodException`.

The launcher configures `ttyS0` and requests console-input support, but those
are config flags only: the caller receives no handle with which to inject
guest UART bytes.  Existing guest output identifies the endpoint as 16550-like
`0x3f8`, so it would be a plausible COM1 KD target if input existed.  It does
not.

```text
AVF_SERIAL_BIDIRECTIONAL_BINARY = BLOCKED
KD_HOST_BRIDGE = NOT_CREATED
BCD_BOOTDEBUG = NOT_APPLIED
WINDOWS_KD_HANDSHAKE = NOT_TESTED
```

No BCD, media, firmware, or tablet runtime state changed.  The block is a
missing public/runtime AVF input endpoint, not UTF-8 conversion or buffering.
Raw capability output, preserved old failure evidence, all methods, and replay
commands are in `docs/KD_TRANSPORT_FEASIBILITY_2026-09-05.md` and
`docs/SESSION_HANDOFF_2026-09-05.md`.

## GOP/WAVF experimental FD candidate — 2026-09-06

The finished r4 artifact is retained as a **runtime candidate**, not a
reproduced build:

```text
EXPERIMENTAL_GOP_FD_CANDIDATE = PASS
NEW_GOP_FD_BUILD = NOT_PASS
KVMTOOL_EFI.fd SHA-256 =
8BB42784791B6618D599EF7552C2CF4DFBA61AE5E07B7F08AC76B3F01F48392C
```

The r4 log ends in `- Done -`; the packed FD contains compressed `FVMAIN`.
The uncompressed r4 `FVMAIN.Fv` and linked `BdsDxe.efi` both contain the
UTF-16 `AVF_GOP_FRAME` marker, while the linked LTO object contains
`AvfEmitGopKeyframe`.  This is sufficient offline evidence that the GOP/WAVF
code is packaged.  The exact prior Windows build environment and a guarded
reproduction entry point are recorded in
`docs/GOP_FD_CANDIDATE_AUDIT_2026-09-06.md` and
`docs/EDK2_KNOWN_GOOD_RESTORE_2026-09-06.md`.

## Native AVF scanout audit

**Result: `NATIVE_AVF_SCANOUT = BLOCKED_BY_SPECIFIC_PERMISSION`.**

Android 16 Terminal implements an actual native path:

```text
Terminal DisplayActivity / SurfaceView
  -> IVirtualizationServiceInternal.waitDisplayService()
  -> ICrosvmAndroidDisplayService.setSurface(surface, isCursor)
  -> crosvm Android display backend -> SurfaceFlinger
```

The cursor uses a second `SurfaceView`, `setCursorStream()`, and a `SurfaceControl.Transaction` overlay. This is not VNC or RDP. AOSP passes crosvm `--android-display-service=<config.name>` when `DisplayConfig` is present.

### Device evidence

Fingerprint:

```text
samsung/gts11xx/gts11:16/BP4A.251205.006/X736BXXS6BZF4_OXM6BZF4:user/release-keys
```

- The privileged APEX Terminal is installed at `/apex/com.android.virt/priv-app/VmTerminalApp@BP4A.251205.006/VmTerminalApp.apk` (version 16).
- Its APK contains `ICrosvmAndroidDisplayService`, `IVirtualizationServiceInternal.waitDisplayService`, `setSurface`, `removeSurface`, and `setCursorStream`.
- Terminal is platform-signed/privileged, has hidden-API policy `0`, and declares `usesNonSdkApi=true`.
- The device registers `android.system.virtualizationservice`; its daemon label is `u:r:virtualizationservice:s0`.
- `crosvm` is present in `/apex/com.android.virt/bin/crosvm`, but an enforcing-SELinux shell cannot read its metadata or strings. Feature strings are therefore not claimed from this binary.
- Terminal's `VmLauncherService` configures `gfxstream`, `gfxstream-vulkan`, and `gfxstream-composer` for its graphical path. This proves Terminal expects the platform graphics backend, not every crosvm compile flag.

### Exact custom-app blocker

`com.example.winavf` has both AVF permissions granted:

```text
MANAGE_VIRTUAL_MACHINE = granted
USE_CUSTOM_VIRTUAL_MACHINE = granted
```

It nevertheless runs as `u:r:untrusted_app:s0:...`. Its opt-in read-only audit produced:

```text
BINDER android.system.virtualizationservice=NULL
CLASS ...IVirtualizationServiceInternal=UNAVAILABLE:ClassNotFoundException
CLASS ...ICrosvmAndroidDisplayService=UNAVAILABLE:ClassNotFoundException
```

The service is listed, but `service check android.system.virtualizationservice` from the shell returns `not found`. This is service-manager access control, not an absent daemon. In AOSP, the service has type `virtualization_service`; `virtualizationservice_use(domain)` grants its `service_manager find` and Binder calls. `untrusted_app` receives no such rule, and the service is not `app_api_service`.

Thus the ordinary AVF permissions allow the existing custom VM through the public manager path, but not the private Binder which hands a `Surface` to crosvm. Shipping generated AIDL stubs cannot fix blocked service discovery. The required change is an OEM/platform-signed bridge or a new public, permission-protected per-VM surface API; either is outside the no-root/no-system-change scope.

## Graphics architecture decision

**Selected research result: `EARLY_WINDOWS_DISPLAY_RELAY = VIABLE`.** This
means viable as an architecture for a separately signed, automatically
serviced user-supplied WinPE image; it is not yet a runtime pass.

### Current GOP framebuffer

The active `ArmVirtKvmTool` source explicitly includes `VirtioGpuDxe`. Its
existing local GOP adaptation creates a virtio-gpu 2D resource, allocates its
BGRA backing pages as `EfiReservedMemoryType`, exposes those pages through
`GopMode.FrameBufferBase`, uses
`PixelBlueGreenRedReserved8BitPerColor`, and leaves the virtio device running
from its ExitBootServices callback. The pages are guest RAM; crosvm consumes
them through `RESOURCE_ATTACH_BACKING`, `TRANSFER_TO_HOST_2D`, and `FLUSH`.

This is a valid *guest-side* physical-LFB handoff candidate for Windows Basic
Display. It is not a handle exported to WinAVF. Blob/dma-buf/AHardwareBuffer
exports stay inside crosvm/gfxstream and its Android display backend; the
ordinary app receives neither an FD nor a resource ID. Therefore:

- `HOST_VISIBLE_PERSISTENT_FRAMEBUFFER = BLOCKED_BY_SPECIFIC_PERMISSION`
- `CONTINUOUS_FIRMWARE_TO_WINDOWS_DISPLAY = NOT_YET_PROVEN`

### Rejected short paths

- `SERVICE_VCPU_DISPLAY_RELAY = NOT_A_SHORT_PATH`: AVF exposes only one CPU or
  match-host topology, and Arm crosvm powers off non-boot vCPUs initially. A
  resident CPU would require PSCI bring-up, memory/device exclusion from
  Windows ACPI, independent vsock transport, and cache/device ownership rules.
  It would also not cause Windows to keep using the GOP buffer.
- `POST_EBS_RESIDENT_FIRMWARE_RELAY = NOT_VIABLE`: UEFI runtime code has no
  autonomous scheduler after EBS. Boot-service events/timers are terminated;
  runtime code runs only when Windows invokes a Runtime Service. Baseline also
  established `SetVirtualAddressMap = NOT_CALLED`.

### Product path

The ordinary app can create its own Android `Surface` and has public VM-vsock
APIs, while the Windows virtio driver project ships ARM64 `viogpudo` (a WDDM
display-only driver) and `viosock` packages. WinPE accepts offline driver
packages and runs PnP during its boot. The feasible product shape is therefore
an automatically serviced boot.wim containing a production-signed ARM64
display-only relay plus a vsock producer; WinAVF renders the received dirty
BGRA tiles to its own Surface. It does not depend on the privileged Android
display broker and can become visible during Setup.

Before altering any WIM, the next PoC is an **offline-only** driver-package
preflight: verify a production-signed ARM64 `viogpudo`/`viosock` package and
that its INF matches the already observed `PCI\\VEN_1AF4&DEV_1050` GPU. If it
passes, make one cloned-media PnP acceptance test. No firmware, BCD, FAT, or
baseline image change is authorized by this research result.

## Repository support

`android-app/src/com/example/winavf/MainActivity.java` has an opt-in read-only `display_host_audit` intent/UI action. It creates no VM, waits for no service, and submits no Surface. It records the calling UID, permission grants, service lookup result, and internal class visibility.

## Sources and local evidence

- AOSP Terminal `DisplayProvider.kt`, commit `aa6989ebf936cc865a156de2fb0591500ed6d242`.
- AOSP Virtualization change introducing `DisplayConfig` and `--android-display-service`, commit `ef450795e2acb4e89369680f68f75415bf437427`.
- AOSP Android 16 QPR2 `service_contexts`, `service.te`, and `te_macros` (`virtualizationservice_use`).
- Non-redistributed local Terminal APK: `%LOCALAPPDATA%\Temp\winavf-display-audit\VmTerminalApp.apk`, SHA-256 `CD101C3545CE936ACD01EF36BBA8E0CFFD3D40203E8ADB6E1BD12BD3BA25623E`.
- Read-only custom-app report: `%LOCALAPPDATA%\Temp\winavf-display-audit\native-avf-display-access-audit.txt`.

No APK, Windows image, ISO, WIM, or other proprietary binary is tracked here.

## Pre-OTA snapshot

Read-only device evidence was captured before the pending Samsung reboot. See
`docs/DEVICE_PRE_OTA_SNAPSHOT_2026-09-05.md`. No OTA, system, APEX, firmware,
Windows-media, or VM state was modified.

## EDK2 host-toolchain reconstruction stop - 2026-09-06

The failed host-toolchain reconstruction branch was stopped and its temporary
tracked BaseTools/GenFds/build-rule edits and shim wrappers were rolled back.
The known-good EDK2 configuration is restored: Source/C BaseTools, regular
Python 3.14, GCC5 AARCH64 toolchain, direct ACPICA IASL, default VfrCompile,
and the original GCC5 make/objcopy rules. No Android, Windows, WIM, BCD, or
product decoder files were changed.

The existing firmware and GUI baseline remain preserved with hashes recorded in
`docs/EDK2_KNOWN_GOOD_RESTORE_2026-09-06.md`. `NEW_GOP_FD_BUILD` remains
`NOT_PASS` until the exact known-good command completes in a normal Windows
developer environment; the sandbox attempt stopped at bare `GenFw` lookup.

## GOP diagnostic-frame packaging boundary — 2026-09-06

The r4 FD has one early `AvfEmitGopKeyframe` capture and no timer, event, or
runtime-configurable later-capture trigger. The source-only follow-up adds one
diagnostic gradient GOP `Blt`, emits a second `WAVF` frame, and restores the
original pixels; it is not in r4 and has not been packaged.

The narrow retry that made MSYS `echo.exe` visible resolved quoted `"echo"`,
but exposed MSYS `sh.exe` to `mingw32-make`; its conversion turns a Windows
source path in a GCC response file into `C:Users...`. The edit was reverted.
This is a host make/shell incompatibility, not a firmware-source failure. No
new FD, patch, tablet image change, or runtime test was made. See
`docs/GOP_WAVF_RUNTIME_POC_2026-09-06.md`.

## AVF UEFI input host probe — 2026-09-06

`AVF_UEFI_INPUT_TRANSPORT = BLOCKED`.  The one isolated test enabled the
public `useKeyboard(true)` VM configuration only and attempted to use the
locally discovered AOSP hidden `VirtualMachine.sendKeyEvent(short, boolean)`
for `KEY_ESC`.  On the actual tablet framework that method is absent:
`NoSuchMethodException`.  This is a host API boundary, not evidence about
guest keyboard enumeration or BDS hotkey handling.

The external immutable image was not patched; its SHA-256 was the known-good
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`
before and after the run.  `AVF_SERIAL_BIDIRECTIONAL_BINARY` remains blocked,
and `GRAPHICAL_UEFI_INPUT = NOT_TESTED`.  Evidence and exact method are in
`docs/AVF_UEFI_INPUT_HOST_PROBE_2026-09-06.md`.

## Post-EBS vsock input preparation — 2026-09-06

The product input route after Windows user-mode starts is now explicitly
`APK → connectVsock(4050) → signed ARM64 viosock → WinAvfInput.exe → SendInput`.
The agent has been built offline as a 4,096-byte ARM64 PE, SHA-256
`CFFDAA8FBDA4BF1B692D9D23A0F3EC28618116E2A95EF2989FECD3617B9FE80F`, with
only `KERNEL32.dll` and `WS2_32.dll` imports. Its first observable is a raw
`WVH1` vsock HELLO; `USER32` is dynamically loaded only on a later key packet.

This is static preparation, not a runtime pass: `WINPE_USERLAND`, viosock
binding, vsock HELLO, Windows input, and WinPE Setup visibility all remain
unconfirmed. No WIM candidate or tablet patch was made. See
`docs/VSOCK_USERMODE_INPUT_DESIGN_2026-09-06.md`.

An offline append-only vsock HELLO WIM candidate is valid but is not staged:
`boot-wim-viogpu-viosock-hello-r1.wim`, SHA-256
`505A774DC101D18A6BE02B63CAE2E6C2037C40662A339D049BD022EDA4D6E9C4`.
Its WIM verify, agent hash and unchanged signed viosock hash pass. Patch
generation stopped safely because the available local raw file is a historical
A3 candidate, not an attested copy of immutable baseline
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.
No tablet media was changed.

## WinPE viosock HELLO runtime — 2026-09-06

One fully audited patch run started `WinAvfInput.exe` plus `wpeinit` from the
preserved signed-driver WIM. The APK retried public `connectVsock(4050)` for
60 seconds but received `No such device`; no `WVH1` was observed. Serial again
stopped at `ER`. The application rolled back its private image and verified it;
the external baseline SHA is again the immutable `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

This is not a viosock driver-failure result: because `WINPE_USERLAND` remains
unobserved, neither agent execution nor PnP binding was established. Therefore
`VSOCK_HELLO = NOT_OBSERVED`, `WINPE_VSOCK_BOUND = NOT_CONFIRMED`, and
`WINDOWS_INPUT_VSOCK = NOT_TESTED`. See
`docs/VSOCK_HELLO_RUNTIME_2026-09-06.md`.

## r9 SetVirtualAddressMap runtime evidence — 2026-09-06

The already completed single r9 runtime was inspected read-only. Its raw serial
log and a byte-identical evidence copy are
`build-logs/runtime-va-r9-20260906/runtime-r9-raw-serial.log` and
`build-logs/runtime-va-r9-20260906/runtime-r9-raw-serial.evidence.log`.
Both match the device `serial.log` SHA-256
`38600F70A9333A5529B3398F25524DB3D972D11C306C97DDCF06924404E696FE`.

The captured stream ends at zero-based byte offsets `1290716..1290718` with
`BES`: wrapper entry, RuntimeDxe ExitBootServices event, then successful return
from the original ExitBootServices. The raw capture writes/flushed bytes before
any text/frame handling; a later read-only device check found the same length
and SHA while the VM remained alive. `VA0` (SetVirtualAddressMap entry) and
`VA1` (VA-change callback) were not observed. Therefore:

```text
POST_EBS_SET_VIRTUAL_ADDRESS_MAP = NOT_OBSERVED
VIRTUAL_ADDRESS_CHANGE            = NOT_OBSERVED
RESULT                            = PASS (negative observation)
```

The r9 FD was `EB023DF0CA527F6E428D5B0CCE87CC67895B4C69443B64661CE7FAD4BD65C346`.
The one-range patch SHA-256 was
`54CC7498867ADFD29AE82320FCEC17FE338B29E69D6E3D9B389E1981DD2AD124`, covering
offset `7250927616`, length `2097152`. The existing launcher rollback then
reported verified success, and an independent full post-rollback SHA-256
returned the immutable baseline
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

Full report: `docs/GOP_R9_RUNTIME_VIRTUAL_ADDRESS_MAP_2026-09-06.md`.

## Kernel-entry observer design — 2026-09-07

The r9 result deliberately does not imply that `ntoskrnl` failed to start. A
read-only design audit established that existing EDK2 `StartImage` evidence
proves only `winload.efi` invocation, not its transfer to the ARM64 kernel.
The only stock signed direct observer is KD, but current public AVF lacks the
required inbound COM1 transport. Thus:

```text
WINDOWS_KERNEL_ENTRY_OBSERVER = BLOCKED
WINDOWS_KERNEL_ENTRY          = UNKNOWN
```

No candidate, firmware, media, BCD, or Android code was built or run for this
design pass. Details: `docs/WINDOWS_KERNEL_ENTRY_FORENSIC_DESIGN_2026-09-07.md`.

## Earliest signed post-EBS milestone research — 2026-09-07

Read-only INF/API audit closed the proposed signed-driver alternative under the
current untrusted-AVF API boundary. `viostor` is the earliest concrete ARM64
candidate (exact `PCI\VEN_1AF4&DEV_1042`, signed boot-start service), but its
normal block I/O has no public app-visible completion or trace. `viosock` and
`viogpudo` are demand-start PnP drivers; vsock connection also requires a
later guest listener, and AVF exports neither device lifecycle nor scanout.

```text
EARLIEST_SIGNED_POST_EBS_MILESTONE = BLOCKED
```

No runtime candidate was created or run. This is an observability constraint,
not a driver/kernel failure result. Details:
`docs/EARLIEST_SIGNED_POST_EBS_MILESTONE_RESEARCH_2026-09-07.md`.

## Expanded post-EBS host observability forensic audit — 2026-09-07

Read-only device/API/source audit found no public raw serial RX, crosvm control
socket, device counter or GZVM trace for an ordinary app. It did establish a
separate safe future host-only instrument: `adb shell` Perfetto can capture
standard scheduler, host-block and host-IRQ events while a WinAVF crosvm runs.
This can prove crosvm survival/scheduling and correlate host activity, but
cannot prove `ntoskrnl` entry or a specific virtio request.

```text
POST_EBS_OBSERVABILITY_PATH = AVAILABLE_WITH_SAFE_ONE_RUN_CONFIG
KD_OVER_CURRENT_CROSVM_UART = CONDITIONAL (only if hidden ttyS0 RX becomes public)
```

No VM was run and no runtime artifact was created. Full matrices, FD inventory,
SELinux boundaries and the proposed non-executed trace are in
`docs/POST_EBS_OBSERVABILITY_FORENSIC_2026-09-07.md`.

## Bounded post-EBS Perfetto runtime — r9 — 2026-09-07

One and only one r9 VM launch used the pre-existing FD and one-range reversible
patch unchanged.  Raw serial again reached `BES`, including the proven return
of the original `ExitBootServices()`.  A 90-second host Perfetto trace began
before the VM start intent.  The launch-specific process was
`crosvm_winavf-gop-ebs-r1` PID `16987`; its `crosvm_vcpu0` TID `17000` received
7,485 scheduler slices and 29,915.517 ms CPU in the conservative trace tail
from 60.000 through 89.930 seconds.  That tail begins after the latest host
sample that already contained `BES`, so it is direct host evidence of ongoing
vCPU execution after EBS.

The same trace saw the VM `virtio_blk` worker only through 26.041 seconds;
there was no VM-attributable block-worker activity in the conservative
post-EBS interval.  Global host block traffic cannot be attributed to the VM.

```text
POST_EBS_VCPU_EXECUTION       = PASS
POST_EBS_BLOCK_ACTIVITY       = NOT_OBSERVED (VM-attributable)
POST_EBS_GLOBAL_BLOCK_ACTIVITY = PASS (not attributable)
```

The launcher immediately performed verified rollback; a fresh independent
external SHA-256 exactly matched immutable baseline
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.  This
does not prove Windows kernel entry or guest forward progress.  Full retained
evidence: `docs/POST_EBS_PERFETTO_R9_RUNTIME_2026-09-07.md`.

## Windows ARM64 early-platform contract audit — 2026-09-07

A read-only comparison of actual r9 FDT observations, r9 ACPI output, the
one-vCPU crosvm launch, upstream ArmVirtKvmTool dynamic FDT parsers, and the
historical eight-vCPU GUI/loader logs found **no concrete ACPI/FDT contract
violation**. The apparent GICR change is topology-correct: `0x3FFD0000 +
0x20000` for one vCPU and `0x3FEF0000 + 0x100000` for eight both end exactly at
the GICD base `0x3FFF0000`. Current MADT has the correct sole enabled
`uid=0/mpidr=0` GICC; GTDT PPIs/flags and FADT HW-reduced/PSCI-HVC flags are
directly derived from the same FDT consumed by firmware before EBS.

The complete static contract is nevertheless not claimed PASS: retained
evidence cannot establish `CNTFRQ_EL0`, actual generic-timer delivery, or the
timer interface selected by Windows. Thus:

```text
WINDOWS_ARM_EARLY_PLATFORM_CONTRACT = INCONCLUSIVE
```

No ACPI/GIC/timer firmware A/B is justified. The next new information requires
a genuine bidirectional KD serial transport or privileged VMM/GZVM tracing.
Full matrix and evidence:
`docs/WINDOWS_ARM_EARLY_PLATFORM_CONTRACT_AUDIT_2026-09-07.md`.

## KVM ftrace post-EBS r9 runtime — 2026-09-07

One new bounded r9 runtime tested KVM ftrace through Perfetto. Raw serial was
byte-identical and again reached `BES`. The WinAVF `crosvm_vcpu0` had 23,635
scheduler slices and 85.312 seconds CPU time, but Trace Processor found zero
`kvm_*`, `vgic_*`, GZVM, or GenieZone packets among 813,164 ftrace events.
Configured KVM tracepoints are therefore not an observable guest-event source
for this unprivileged custom VM.

The launcher immediately rolled back the existing r9 range and displayed
verified rollback; the external immutable image again hashed exactly to
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

```text
KVM_FTRACE_PERFETTO_FOR_WINAVF = NOT_USABLE
VMM_GUEST_EVENT_OBSERVER        = BLOCKED
WINDOWS_KERNEL_ENTRY            = UNKNOWN
```

Full raw/decoded trace inventory and analysis:
`docs/KVM_FTRACE_POST_EBS_R9_RUNTIME_2026-09-07.md`.

## ADB-shell AVF console / KD feasibility — 2026-09-07

The production APEX supplies shell CLI `vm`; `vm run` documents distinct
`--console` and `--console-in` FDs for a separate shell-created VM. It does not
export the hidden console-input FD of app-owned WinAVF. `vm console` is a
TTY/`microcom` PTY route, not a proven raw binary bridge. Production
`ro.debuggable=0` disables framework host-console provisioning; the only live
Terminal VM enumerated by shell has `hostConsoleName: None`.

Pre-runtime classification was:

```text
ADB_SHELL_AVF_CONSOLE_RX       = AVAILABLE_ONLY_FOR_SHELL_CREATED_VM
ADB_SHELL_BIDIRECTIONAL_COM1   = CONDITIONAL
SHELL_VM_TOPOLOGY_EQUIVALENT   = PARTIAL
KD_DEBUG_ONLY_PATH             = CONDITIONAL
```

No VM/media was touched. A separately authorized shell-owned raw-byte loopback
is prerequisite to any BCD/KD test and cannot prove WinAVF equivalence absent
FDT/crosvm comparison. The immediately following loopback runtime supersedes
the provisional COM1/KD statuses. Evidence:
`docs/ADB_SHELL_AVF_CONSOLE_KD_FEASIBILITY_2026-09-07.md`.

## Shell serial pipe loopback runtime — 2026-09-07

The first one-shot shell loopback created CID `2098` but supplied a regular
file to `--console-in`; crosvm therefore rejected it at epoll registration.
There was no attributable AVC denial. A second separately authorized
non-Windows loopback changed only that input object to an inherited anonymous
pipe. It created CID `2099`, logged `input=... (pipe:[4923896])`, echoed all
4,096 repeated `00..FF` bytes exactly, requested PSCI shutdown, and returned
`VM_EXIT=0`. The temporary shell directory was removed after evidence capture.

```text
SERIAL_WAIT_CONTEXT_EPERM            = NON_POLLABLE_REGULAR_FILE
AVC_OR_SELINUX_DENIAL                = NOT_OBSERVED
SHELL_RAW_SERIAL_TX                  = PASS
SHELL_RAW_SERIAL_RX                  = PASS
SHELL_BINARY_TRANSPARENT_COM1        = PASS
ADB_SHELL_BIDIRECTIONAL_COM1         = YES (shell-created VM only)
KD_DEBUG_ONLY_PATH                   = AVAILABLE (diagnostic shell-VM path)
KD_HOST_BRIDGE                       = NOT_YET_RUN
```

PTY `vm console` remains unsuitable. The next separately authorized step may
be a diagnostic Windows clone plus a minimal reversible BCD bootdebug test;
its topology must still be compared with WinAVF. Evidence:
`docs/SHELL_SERIAL_PIPE_LOOPBACK_RUNTIME_2026-09-07.md`.

## Shell KD BCD preflight — 2026-09-07

An attested host-only clone of the Android external immutable baseline was
created; its full SHA-256 matched
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`. An
elevated BCDEdit run configured only a separately extracted BCD copy for
`bootdebug`, kernel `debug`, and serial COM1/115200. It did not enable test
signing or modify any Windows media.

The BCD grew from 16,384 to 20,480 bytes. GNU mtools 4.0.49 was found locally
and used directly against the existing FAT32 ESP at raw byte offset 1,048,576;
this is a standard FAT writer, not a manual allocator. It replaced only
`\EFI\Microsoft\Boot\BCD`, allocated one extra 8,192-byte FAT cluster, and
read back the exact KD BCD SHA. The full clone SHA changed from immutable
baseline `2582...278A7` to host-only KD candidate
`563DA01DB2DADDA202B8475D280E064F0C5C5B60DC07ACA61B6009C38147C196`.
No Android staging or shell Windows VM/KD run occurred.

```text
SHELL_KD_MEDIA_CLONE    = PASS
BCD_BOOTDEBUG_CANDIDATE = PASS
BCD_BOOTDEBUG_INJECTED  = PASS (host-only disposable clone)
WINDOWS_KD_HANDSHAKE    = NOT_TESTED
```

## Shell-owned Windows KD runtime — 2026-09-07

One shell-owned Windows diagnostic VM (CID `2100`) was run with the already
injected disposable KD clone, a local named-pipe `kd.exe` endpoint, and the
same `ttyS0` COM1 configuration used by the successful Android-shell-local
loopback. The Android-staged clone rehashed exactly as
`563DA01DB2DADDA202B8475D280E064F0C5C5B60DC07ACA61B6009C38147C196`.
The shell VM reached U-Boot, EDK2, Windows Boot Manager and `Loading files...`.

However `vm run` recorded `Failed to create wait context. Operation not
permitted (os error 1)` for the serial input descriptor inherited through
`adb exec-out`. KD opened its local named pipe and transmitted synchronizing
bytes, but received no KD packet and remained at `Waiting to reconnect...`.
This does not test Windows KD because crosvm rejected the required COM1 RX
descriptor. The bounded run ended with timeout `124`; CID `2100` is gone and
no second runtime was run. After host evidence extraction, the exact temporary
shell staging directory was removed (`CLEANUP_PASS`).

```text
KD_HOST_NAMED_PIPE          = PASS
SHELL_KD_COM1_RX_AT_RUNTIME = FAILED (wait-context EPERM; FD type unverified)
WINDOWS_KD_HANDSHAKE        = INCONCLUSIVE
WINDOWS_KERNEL_ENTRY        = UNKNOWN
```

Evidence: `docs/SHELL_WINDOWS_KD_RUNTIME_2026-09-07.md`.

## ADB shell COM1 FD audit — 2026-09-07

No VM was launched. A minimal Android ARM64 descriptor helper proved that the
previous KD `EPERM` was caused by the runner's background subshell: Android
`sh` replaced its stdin with `/dev/null`, and `epoll_ctl(ADD)` on that reopened
descriptor returns `EPERM` exactly as crosvm logged.

Direct `adb exec-out` stdin is a pollable PTY. Direct `adb shell -T` stdin is
a pollable socket, but reopening `/proc/self/fd/0` fails with `ENXIO`. AOSP
`vm run` solves that cleanly when `--console-in` is omitted: it duplicates the
actual stdin FD rather than reopening a path. Therefore the correct next
non-Windows validation is foreground `adb shell -T` plus **no**
`--console-in`, not another Windows run.

```text
ADB_SHELL_T_STDIN_POLLABLE        = PASS (socket)
ADB_SHELL_T_VM_DEFAULT_STDIN_PATH = AVAILABLE
KD_PREVIOUS_RX_FAILURE             = BACKGROUND_STDIN_TO_DEV_NULL
WINDOWS_KD_HANDSHAKE               = INCONCLUSIVE (unchanged)
```

Evidence: `docs/ADB_SHELL_COM1_FD_AUDIT_2026-09-07.md`.

## Shell-T text-safe COM1 loopback — 2026-09-07

One further disposable **non-Windows** VM (CID `2102`) used foreground
`adb shell -T` and the default stdin path, with Base64 ASCII decoded into the
raw Android pipe.  The bare guest returned a 4,096-byte `00..FF` payload with
an exact SHA-256 match (`C8F5...EC193`) in the Android raw console file;
crosvm exited normally and did not log a wait-context error.  This validates
the missing host-to-guest raw COM1 path without altering Windows media or the
product baseline.

ADB's live stdout remained text-like and did not return the binary echo as a
raw host stream.  Therefore this is not yet an interactive WinDbg bridge:
the next bounded engineering task is an outbound raw-console-to-Base64 relay,
followed by a disposable loopback decode check.  No second Windows KD run is
authorized or justified before that check.

```text
HOST_TO_GUEST_RAW_COM1       = PASS (text-framed ingress)
GUEST_TO_DEVICE_RAW_COM1     = PASS
HOST_RAW_KD_RETURN_STREAM    = NOT_YET_AVAILABLE
WINDOWS_KD_HANDSHAKE         = INCONCLUSIVE
```

Evidence: `docs/SHELL_T_BASE64_COM1_LOOPBACK_RUNTIME_2026-09-07.md`.

## Full shell-T text-framed COM1 loopback — 2026-09-07

The second half of the diagnostic bridge is now proved.  A disposable
non-Windows loopback carried `00..FF` repeated for 4,096 bytes through a
continuous Base64 ingress pipe and `O:<Base64>` console-file egress records.
The decoded return is byte-exact (`C8F5...EC193`); the final full serial record
is `0C1B...F5597`.  No crosvm wait-context error was present.

Shell SELinux denies `mkfifo` under `/data/local/tmp`; that had created a
regular file and explains the intermediate EPERM exactly.  The final path uses
the source-proven `base64 -di | vm run` anonymous pipe with no
`--console-in` argument.

```text
SHELL_BINARY_TRANSPARENT_COM1 = PASS (text-framed host bridge)
KD_HOST_TRANSPORT_PREREQUISITE = PASS
WINDOWS_KD_HANDSHAKE = INCONCLUSIVE (no repeat yet)
```

Evidence: `docs/SHELL_T_FRAMED_COM1_LOOPBACK_RUNTIME_2026-09-07.md`.

## Shell Windows KD framed runtime — 2026-09-07

One shell-owned disposable Windows KD clone run was made after full framed
COM1 loopback proof.  The staged clone SHA exactly matched
`563DA01D...47C196`.  KD connected to the local named pipe and transmitted
483 synchronization bytes, while the bridge captured 32,679 guest UART bytes.
The VM reached U-Boot, EDK2, Windows Boot Manager and `Loading files...`.

No crosvm EPERM occurred, but no Windows KD packet arrived and WinDbg stayed
at `Waiting to reconnect`.  Thus this is a genuine negative handshake result,
not a host-to-guest RX failure.  The one run timed out; no repeat was made.
The exact temporary Android directory was deleted, and the immutable product
baseline was independently rehashed as
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

```text
KD_HOST_NAMED_PIPE            = PASS
SHELL_BINARY_TRANSPARENT_COM1 = PASS
SHELL_KD_COM1_RX_AT_RUNTIME   = PASS
WINDOWS_KD_HANDSHAKE          = NOT_OBSERVED
WINDOWS_KERNEL_ENTRY          = UNKNOWN
```

Evidence: `docs/SHELL_WINDOWS_KD_FRAMED_RUNTIME_2026-09-07.md`.

## Shell KD BCD/serial audit — 2026-09-07

The read-only post-run audit found one concrete omission: the injected BCD
correctly enables `{default}.bootdebug`, `{default}.debug`, and serial COM1
115200 settings, but it does **not** enable `{bootmgr}.bootdebug`.  Microsoft
documents Boot Manager, boot loader, and kernel debugging as separate stages.
The previous non-handshake therefore did not cover the earliest available
Boot Manager KD event, although it still remains a valid negative result for
the actually reached later path.

No runtime or modification occurred.  A single BCD-only disposable A/B that
adds `{bootmgr}.bootdebug` is the next lowest-cost diagnostic, if separately
authorized.

```text
KERNEL_KD_BCD_CONFIGURATION = PASS
BOOTMGR_BOOTDEBUG           = NOT_ENABLED
COM1_MAPPING                = PASS
```

Evidence: `docs/SHELL_KD_BCD_SERIAL_AUDIT_2026-09-07.md`.

## Shell KD Boot Manager BCD A/B — 2026-09-07

One new disposable clone added only `{bootmgr}.bootdebug = Yes`.  It was
offline audited, staged with exact SHA `652EEC53...FA38E7`, and run exactly
once through the already proven framed COM1 bridge (CID `2109`).  The prior
candidate showed Boot Manager UI and `Loading files...`; the new candidate
stopped immediately after `IMAGE_AUDIT start enter` for `BOOTAA64.EFI` and
never emitted `Loading files...`.  KD sent 513 bytes but received no target
packet.

This is a real Boot Manager configuration effect, not an EPERM/transport
failure.  It proves the flag is consumed, but not that the KD protocol starts.
The disposable staging was deleted and immutable product baseline SHA was
reconfirmed exact.

```text
BOOTMGR_BOOTDEBUG_EFFECT = PASS
SHELL_KD_COM1_RX         = PASS
WINDOWS_KD_HANDSHAKE     = NOT_OBSERVED
```

Evidence: `docs/SHELL_WINDOWS_KD_BOOTMGR_AB_RUNTIME_2026-09-07.md`.

Evidence: `docs/SHELL_KD_BCD_PREFLIGHT_2026-09-07.md`.

## ARM64 KD serial platform-contract audit — 2026-09-07

A read-only audit of the current ArmVirtKvmTool source and preserved serial
evidence confirms one coherent UART description: crosvm `ttyS0` is observed
at MMIO `0x3f8`; EDK2 uses the 16550 MMIO library; the FDT `stdout-path`
record flows into SPCR, DBG2 and ACPI `\\_SB_.COM0`.  SPCR uses
`SystemMemory`, while the FDT parser selects Microsoft-recommended 16550 with
GAS subtype `0x12`, byte access and 115200.  No x86-I/O, PL011, baud, or
namespace mismatch was found.

The exact runtime-generated ACPI table bytes and UART interrupt number were
not captured, so this is a source/evidence contract result rather than a
runtime-table dump.  It does not change the completed negative KD handshake.

```text
ARM64_KD_SERIAL_PLATFORM_CONTRACT = PASS
SPCR_DBG2_GAS_MODEL               = PASS
ACTUAL_ACPI_TABLE_BYTES           = NOT_CAPTURED
WINDOWS_KD_HANDSHAKE              = NOT_OBSERVED
```

Evidence: `docs/ARM64_KD_SERIAL_PLATFORM_CONTRACT_AUDIT_2026-09-07.md`.

## Explicit `kdcom.dll` shell KD A/B — 2026-09-08

The final low-risk BCD ambiguity was tested once on a new disposable shell
clone.  The only intended media delta was `{default}.dbgtransport = kdcom.dll`;
`{bootmgr}.bootdebug` remained off.  Offline BCD read-back, ESP audit,
`BOOTAA64.EFI` comparison, and staged raw SHA all passed.  The shell VM
reached `Loading files...`; the byte-exact bridge delivered 513 host KD bytes
and returned 32,678 UART bytes without a crosvm wait-context error.  KD still
received no target packet.

The disposable staging directory was removed, no VM remains, and the
immutable Android baseline was rehashed exactly after cleanup.

```text
EXPLICIT_KDCOM_BCD_CONFIGURATION = PASS
SHELL_KD_COM1_RX_AT_RUNTIME      = PASS
SHELL_WINDOWS_BOOT_PATH          = PASS
WINDOWS_KD_HANDSHAKE             = NOT_OBSERVED
WINDOWS_KERNEL_ENTRY             = UNKNOWN
```

Evidence: `docs/SHELL_WINDOWS_KD_EXPLICIT_KDCOM_RUNTIME_2026-09-08.md`.

One elevated fixed-VHD materialization was attempted with only the raw clone as
input. The VHD was detached by cleanup, no exported KD raw candidate or report
was produced, and no Android staging/Windows VM run followed. Do not repeat the
full copy until bounded elevated error capture is in place.

## GenieZone ftrace post-EBS r9 runtime — 2026-09-07

The final accessible vendor VMM observer was tested once with the unchanged r9
patch.  Android exposes the `geniezone` group and Perfetto accepted
`mtk_vcpu_exit`, `mtk_hypcall_enter`, and `mtk_hypcall_leave`, but the decoded
95-second trace yielded zero such packets.  The actual `crosvm_vcpu0` still
received 24,302 slices / 85.551 seconds CPU, so the negative result is about
the trace provider's visibility, not VM execution or Windows kernel entry.

The immediate launcher rollback was verified and the independent external
baseline SHA-256 exactly matched immutable baseline
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

```text
GENIEZONE_FTRACE_PERFETTO_FOR_WINAVF = NOT_USABLE
VMM_GUEST_EVENT_OBSERVER              = BLOCKED
WINDOWS_KERNEL_ENTRY                  = UNKNOWN
```

No repeat with the same provider is justified.  Evidence:
`docs/GENIEZONE_FTRACE_POST_EBS_R9_RUNTIME_2026-09-07.md`.

## r10 installed ACPI serial audit — 2026-09-08

The one authorized r10 firmware-only A/B captured the actual installed ACPI
serial contract before Windows Boot Manager. SPCR is present in the XSDT and
describes the FDT console UART at `0x3F8`; DBG2 is present in the XSDT and
describes a distinct 16550-with-GAS debug UART at `0x2F8` under
`\_SB_.COM0`. This corrects the earlier source-only assumption that both
tables named one UART. The DynamicTables FDT parser intentionally selects
`stdout-path` for the console object and the first non-console serial node for
the debug object.

The r10 run again reached final raw marker `BES`; `VA0/VA1/VA2` were absent.
The launcher rolled back the one 2 MiB firmware range and verified the private
runtime image. The external immutable source image was independently rehashed
before and after rollback as exact baseline
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

```text
INSTALLED_ACPI_SERIAL_TOPOLOGY = PASS
SPCR_CONSOLE_UART              = 0x3F8
DBG2_DEBUG_UART                = 0x2F8
WINDOWS_KD_HANDSHAKE            = NOT_OBSERVED
```

No further KD/Windows run is authorized by this result. The next diagnostic
must first prove whether the shell crosvm path can attach to the second UART
backend byte-for-byte, or separately authorize a one-parameter firmware A/B
that aligns DBG2 with the proven console backend.

Evidence: `docs/R10_ACPI_SERIAL_RUNTIME_2026-09-08.md`.

## Second-UART shell backend audit — 2026-09-08

No second-UART loopback was launched because the available AVF contract cannot
attach one. The actual product crosvm invocation creates `ttyS0` (serial num 1)
with the caller's output and input FDs, then creates `ttyS1` (serial num 2) as
the virtualization service's output-only failure pipe. The retained source
accepts only `ttyS0` or `hvc0` for console input and rejects `ttyS1`; the shell
CLI has no arbitrary `--serial` option.

Together with r10, this establishes that the byte-exact shell bridge reaches
`0x3F8`, whereas Windows DBG2 points at unexposed `0x2F8`. The absence of KD
packets is therefore explainable by serial topology rather than a failed host
RX bridge. No product or shell Windows VM was run for this audit.

```text
SECOND_UART_SHELL_BACKEND = NOT_EXPOSED
SHELL_SECOND_UART_LOOPBACK = BLOCKED
WINDOWS_KD_HANDSHAKE = NOT_OBSERVED
```

The next candidate requires separate authorization: one firmware-only A/B
aligning DBG2 and `COM0._CRS` to the already-proven `0x3F8` console UART, with
SPCR and all Windows/Android artifacts unchanged.

Evidence: `docs/SECOND_UART_SHELL_BACKEND_AUDIT_2026-09-08.md`.

## r11 debug-UART alignment runtime — 2026-09-08

The separately authorized one-parameter firmware A/B is complete.  Kvmtool
now copies the FDT console-port Configuration Manager object into the
serial-debug-port object, without modifying the generic FDT parser.  This
makes DBG2 and the source-proven `\\_SB_.COM0._CRS` fixup describe the same
bidirectional console UART (`0x3F8`) already described by SPCR.

One r11 run recorded the installed records `SP=...03F8` and `DG=...03F8`, then
again reached complete `BES`.  The self-verifying one-range patch was rolled
back; launcher UI and an independent external-image SHA check both confirmed
the exact immutable baseline `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

```text
ACPI_DBG2_CONSOLE_ALIGNMENT = PASS
SPCR_CONSOLE_UART           = 0x3F8
DBG2_DEBUG_UART             = 0x3F8
EXIT_BOOT_SERVICES_RETURN   = PASS
WINDOWS_KD_HANDSHAKE        = NOT_TESTED_BY_R11
```

No Windows/KD run was added to this firmware-only A/B.  The next distinct,
authorized test may be one disposable shell-owned Windows KD run using r11
and the existing audited serial-KD BCD candidate.

Evidence: `docs/R11_DEBUG_UART_ALIGNMENT_RUNTIME_2026-09-08.md`.

## Shell Windows KD with r11 UART alignment — 2026-09-08

One disposable shell-owned Windows VM tested the already audited serial KD
BCD candidate with r11’s installed `SPCR=DBG2=0x3F8` mapping.  The exact
framed COM1 bridge again worked: KD connected and sent 513 bytes, while the
guest returned 32,528 raw UART bytes with an independently identical device
capture.  The VM reached Windows Boot Manager and `Loading files...`, but KD
received no target packet before the bounded timeout.

Crucially, this shell clone did not emit `BES` in the time window. The outcome
therefore does not distinguish a post-EBS Windows problem from a shell-clone
timing/topology difference before that boundary. The local clone firmware
range was rolled back, the verified 9-GB shell staging directory was removed,
no VM remained, and the product Android baseline rehashed exactly.

```text
ACPI_DBG2_CONSOLE_ALIGNMENT = PASS
SHELL_KD_COM1_RX_AT_RUNTIME = PASS
SHELL_WINDOWS_BOOT_PATH     = PASS (through Loading files...)
SHELL_EBS_BOUNDARY          = NOT_OBSERVED
WINDOWS_KD_HANDSHAKE        = NOT_OBSERVED
WINDOWS_KERNEL_ENTRY        = UNKNOWN
```

Do not repeat blind KD/BCD variants. Evidence:
`docs/SHELL_WINDOWS_KD_R11_ALIGNMENT_RUNTIME_2026-09-08.md`.

## Shell r11 baseline-BCD control — 2026-09-08

One final bounded shell control removed the serial-KD BCD candidate while
keeping the r11 firmware mapping and shell VM shape.  It still reached only
Windows Boot Manager / `Loading files...` and did not emit `BES` within the
same 100-second window.  The shell diagnostic topology therefore fails to
reproduce the product’s proven EBS boundary independently of KD.

The r11 range was rolled back from the disposable clone, the exact remote
9-GB staging directory was deleted, no VM remained, and the Android product
baseline rehashed exactly to `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

```text
SHELL_R11_BASELINE_BCD_CONTROL = COMPLETE
SHELL_EBS_CONTROL              = NOT_OBSERVED
SHELL_KD_BCD_CAUSES_PRE_EBS_DIVERGENCE = NO
SHELL_VM_TOPOLOGY_EQUIVALENT   = NO (at EBS)
WINDOWS_KD_HANDSHAKE            = NOT_OBSERVED / non-diagnostic for product
```

Evidence: `docs/SHELL_R11_BASELINE_BCD_CONTROL_RUNTIME_2026-09-08.md`.

## Hidden API console RX and native display probe — 2026-09-09

One bounded, app-owned probe established that Samsung's installed
`VirtualMachine.getConsoleInput()` exists and returns a usable `OutputStream`
when the global hidden-API policy is temporarily `1`.  The setting was restored
to its original absent value, the probe VM was never run and was deleted, and
the product runtime image remained exact.

The same before/after audit did **not** expose the private display service:
`ServiceManager.getService("android.system.virtualizationservice")` stayed
`NULL`, and the required internal AIDL stubs remain Terminal-only.  No raw
Binder call was attempted.

```text
HIDDEN_API_POLICY_BOOTSTRAP       = PASS
PRODUCT_APP_CONSOLE_INPUT_API     = PASS
APP_OWNED_BINARY_CONSOLE_RX       = NOT_TESTED
DISPLAY_SET_SURFACE_DIRECT_APP    = SERVICE_NOT_EXPOSED
DIRECT_APP_NATIVE_CROSVM_DISPLAY  = NOT_CONFIRMED
DISPLAY_ACCESS_GATE               = SELINUX
SHIZUKU_DISPLAY_BROKER            = REQUIRES_VM_HANDLE_TRANSFER
PRODUCT_BASELINE_RESTORED         = PASS
```

Evidence: `docs/HIDDEN_API_RX_AND_NATIVE_DISPLAY_PROBE_2026-09-09.md`.

## App-owned binary console loopback — 2026-09-09

The hidden-API `getConsoleInput()` discovery has now been tested end-to-end
without Windows. A 360-byte ARM64 no-disk echo guest at the product AVF
console (`ttyS0` / `0x3f8`) returned the exact 4,096-byte `00..FF` ×16 pattern
through `getConsoleOutput()`. Both in-app and independent offline SHA-256
checks matched, including NUL, CR/LF, DEL, and high-bit values. The disposable
VM was explicitly stopped and deleted; policy and product media were restored.

```text
APP_OWNED_BINARY_CONSOLE_RX       = PASS
APP_OWNED_BINARY_CONSOLE_TX       = PASS
APP_OWNED_BINARY_TRANSPARENT_COM1 = PASS
PRODUCT_BASELINE_RESTORED         = PASS
```

This makes a product-equivalent serial-KD experiment technically possible, but
that BCD/media-changing runtime is a separate authorization boundary.

Evidence: `docs/APP_OWNED_BINARY_CONSOLE_LOOPBACK_RUNTIME_2026-09-09.md`.

## Product app-owned serial KD runtime — 2026-09-09

One product-equivalent serial-KD run proved the full raw host named-pipe →
Android localhost → `getConsoleInput()/getConsoleOutput()` → guest `ttyS0`
path, but it did not reach Windows. KD synchronization bytes arrived while
U-Boot still accepted serial input and stopped autoboot at `Hit any key to
stop autoboot`.

```text
KD_HOST_NAMED_PIPE       = PASS
PRODUCT_APP_KD_BRIDGE    = PASS
APP_OWNED_BINARY_COM1    = PASS
PREBOOT_SERIAL_COLLISION = PASS
WINDOWS_KD_HANDSHAKE     = INCONCLUSIVE
```

No second VM run occurred. The VM was stopped, transaction rollback restored
both app-private and external baseline SHA `2582CAE4...1278A7`, and hidden API
policy returned to `null`. A future test must gate KD TX until a post-U-Boot
serial marker appears. Evidence: `docs/PRODUCT_APP_OWNED_KD_RUNTIME_2026-09-09.md`.

## Direct post-EBS Windows observability audit — 2026-09-09

An exhaustive read-only audit of AVF, GenieZone/GZVM, Android kernel tracing,
debugfs/sysfs, Perfetto, simpleperf, vendor HAL and AVF CLI endpoints found no
direct guest-state observer for the exact app-owned product VM.

```text
DIRECT_POST_EBS_WINDOWS_OBSERVABILITY = BLOCKED
SHELL_GUEST_GDB_PC_OBSERVER            = BLOCKED
PRODUCT_APP_GDB_PC_OBSERVER             = BLOCKED
```

The host kernel contains relevant KVM entry/exit, WFX, fault, IRQ/vGIC and
timer tracepoints, but the enforcing ADB shell cannot read or enable them.
`/dev/gzvm` exists but SELinux denies even a zero-byte open before an ioctl.
GZVM events are absent from tracefs; Perfetto exposes generic ftrace only.
Samsung's exposed HyPer dump contains host QoS/request data, not guest state.

The documented raw shell crosvm `--gdb` route was tested with a read-only
baseline clone. Samsung VirtMgr rejected it before VM creation as
non-debuggable both with its documented default and with explicit `--debug
full`; it cannot observe guest PC. The product configuration enables debug
full and has both custom-VM permissions, but its installed builder exposes no
GDB-port setter. Do not start another BCD/KD or raw shell-GDB experiment. First
prove a supported product `gdbPort` configuration path.

Evidence: `docs/DIRECT_POST_EBS_WINDOWS_OBSERVABILITY_AUDIT_2026-09-09.md`.
Runtime evidence: `docs/SHELL_CROSVM_GDB_ENDPOINT_RUNTIME_2026-09-09.md`.

The follow-up no-VM configuration audit closed the remaining condition. The
product custom-image VM is always converted to `VirtualMachineRawConfig`, and
the framework conversion has no `gdbPort` assignment; the AppConfig
`CustomConfig.gdbPort` facility is not on this path. A private AIDL-parcel
mutation would be a Binder bypass and is out of scope.

```text
PRODUCT_GDB_PORT_CONFIGURABILITY = FAIL
PRODUCT_APP_GDB_PC_OBSERVER      = BLOCKED
```

Evidence: `docs/PRODUCT_GDB_PORT_CONFIGURATION_AUDIT_2026-09-09.md`.

## Persistent Windows Setup witness — 2026-09-09

With direct KD/GDB observability closed, a read-only audit selected the first
standard persistent artifact with a defensible positive-only meaning. The
baseline is RAM-disk WinPE: `Bootstat.dat`, `ntbtlog.txt`, EventLog/registry
state and dumps are either volatile (`X:`), BCD-dependent, later/error-only,
or storage-inapplicable. The selected standard mechanism was
`Microsoft-Windows-Setup/LogPath`, configured solely on a disposable clone by
root `Autounattend.xml`. It assigns the existing disk-0/partition-1 FAT ESP
`C:` with `WillWipeDisk=false`, then asks Setup to write `C:\SETUPACT.LOG` /
`C:\SETUPERR.LOG`.

Exactly one 100-second product-equivalent VM run ended at the known `ER`
post-EBS serial boundary. The stopped clone had its exact pre-run candidate
SHA and neither Setup log existed, proving no FAT sector write during the
bound. The private clone was deleted and the immutable Android baseline was
again exact.

```text
PERSISTENT_WINDOWS_SETUP_WITNESS = NOT_OBSERVED
WINDOWS_KERNEL_EXECUTION_AFTER_EBS = NOT_OBSERVED
PERSISTENT_EARLY_DISK_WRITE = NOT_OBSERVED
IMMUTABLE_BASELINE_RESTORED = PASS
```

`NOT_OBSERVED` is deliberately not a kernel-failure verdict: this witness is
later than NT kernel entry. Do not reopen KD/GDB/BCD on its basis. Evidence:
`docs/PERSISTENT_WINDOWS_BOOT_WITNESS_AUDIT_2026-09-09.md`.

## Synthetic post-EBS P0 runtime — 2026-09-10

One firmware-only P0 application replaced Windows for exactly one bounded
run.  Its raw post-EBS sequence was `BES → P1 → P2 → P3 → P4 → PR`: the
original EBS call returned successfully, then the application proved direct
UART, volatile RAM, and `CNTVCT_EL0` progression before requesting reset.
The 2 MiB one-range transaction was rolled back and the immutable baseline
was again exact.

```text
SYNTHETIC_POST_EBS_P0     = PASS
POST_EBS_EXECUTION        = PASS
POST_EBS_RAW_UART         = PASS
POST_EBS_VOLATILE_RAM     = PASS
POST_EBS_CNTVCT_PROGRESS  = PASS
POST_EBS_GIC_TIMER_IRQ_WFI = NOT_TESTED
```

The only next platform experiment is P1: probe-owned re-arm of GICv3/virtual
timer PPI 27 and a bounded WFI wakeup.  Evidence:
`docs/SYNTHETIC_POST_EBS_P0_RUNTIME_2026-09-10.md`.

## Synthetic post-EBS P1 runtime — 2026-09-10

The corrected P1 firmware-only probe passed.  P1 caches its GICD base and
timer PPI while PCD/Boot Services are valid, then after the proven original
EBS return it restores the minimal GICv3 Group-1 path, enables virtual-timer
PPI 27, arms `CNTV_TVAL_EL0`, and executes one `WFI`.

```text
SYNTHETIC_POST_EBS_P1        = PASS
POST_EBS_GICV3_REARM         = PASS
POST_EBS_VIRTUAL_TIMER_PPI27 = PASS
POST_EBS_WFI_WAKEUP          = PASS
POST_EBS_PLATFORM_CONTRACT   = PASS
```

The one corrected run's raw sequence was `BES → T0 → T1 → T2 → T3 → TR`
(`BES` and `T0` are adjacent raw records and appear as `BEST0`).  `T2` proves
the probe-owned timer IRQ handler ran; `T3` proves that IRQ woke `WFI`.
Rollback and the immutable Android baseline SHA were exact.

The first P1 attempt faulted in PcdDxe immediately after EBS because the probe
incorrectly read a PCD after EBS.  It was rolled back; the corrected run caches
that value before EBS and has no post-EBS PCD access.  This was a probe defect,
not a platform failure.

Evidence: `docs/SYNTHETIC_POST_EBS_P1_RUNTIME_2026-09-10.md`.

## Windows 11 IoT LTSC 2024 Setup A/B — 2026-09-10

The user selected a Windows-only media A/B instead of the proposed Linux
platform test.  A standard Windows-FAT32 materialization replaced only
`\SOURCES\BOOT.WIM` with the official ARM64 LTSC 2024 Setup WIM, build
26100.1742.  FAT32/CHKDSK, WIM verification, index 2 readability, BCD and
BOOTAA64 stability, patch overlay and rollback overlay all passed.

One 120-second app-owned run did **not** reproduce the known-good
`Loading files... -> BES/ER` boundary.  Its serial ended after the existing
firmware's `AVF_BDS_START_IMAGE \EFI\BOOT\BOOTAA64.EFI` path and before
`Loading files...`, `BES`, or `ER`.  The private clone was deleted and the
immutable Android baseline was exactly restored.

```text
LTSC_26100_1742_SETUP_MEDIA = INCOMPATIBLE_BEFORE_KNOWN_EBS_BOUNDARY
WINDOWS_SETUP_INSTALLER     = NOT_REACHED
IMMUTABLE_BASELINE_RESTORED = PASS
```

Do not repeat alternate Setup-WIM swaps.  Evidence:
`docs/LTSC_26100_1742_SETUP_AB_RUNTIME_2026-09-10.md`.

## EFI memory-map handoff audit — 2026-09-10

A read-only review found no concrete EFI map/MapKey defect.  The EBS wrapper
forwards Windows' MapKey unchanged to the original service; the historical
post-return marker proves that original EBS returned success.  `GetMemoryMap`
is not hooked.  The captured BDS map matches FDT DRAM (`0x80000000` plus 4
GiB) and runtime descriptors carry the runtime attribute.  The old
`CONVERT_AUDIT ... Not Found` records address known non-RAM diagnostic targets
before EBS and recur in a run that reaches EBS success.

```text
EFI_MEMORY_MAP_HANDOFF_HYPOTHESIS = NO_CONCRETE_DEFECT_FOUND
WINDOWS_EBS_HANDOFF               = PASS
```

Do not make speculative RAM/ACPI/runtime-map changes.  Evidence:
`docs/EFI_MEMORY_MAP_HANDOFF_AUDIT_2026-09-10.md`.

## Installed Windows system-disk feasibility — 2026-09-10

The proposed installed-Windows diagnostic is not a short replacement for the
existing Setup medium.  The present VM disk is one 9-GB FAT32 partition, while
the current firmware packages FAT but no NTFS UEFI driver.  Applying the
4.2-GB compressed LTSC `install.wim` requires a larger disk plus a FAT ESP and
an NTFS system partition.  That is a new storage topology and only a separate
diagnostic boot class, not an evidence-backed installer fix.

```text
INSTALLED_WINDOWS_DISK_ON_CURRENT_9GB_FAT_TOPOLOGY = NOT_FEASIBLE
INSTALLED_WINDOWS_DISK_REQUIRES_NEW_STORAGE_TOPOLOGY = YES
```

Evidence: `docs/INSTALLED_WINDOWS_DISK_FEASIBILITY_2026-09-10.md`.

## Product KD gated on post-EBS `BES` — 2026-09-10

One exact product run used the already-built BCD+r11 transaction and withheld
both `kd.exe` and all host serial TX until the unique raw `BES` marker.  The
app-owned bridge and private VM started, but the BCD-debug path stopped after
the known `IMAGE_AUDIT`/`CONVERT_AUDIT` tail and did not reproduce `BES` in
150 seconds.  Consequently KD TX was 0 bytes and a post-EBS handshake was
not tested.  Remote rollback and an independent Android hash check restored
the immutable baseline exactly.

```text
BES_GATE_OBSERVED          = NOT_OBSERVED
POST_EBS_KD_TX             = NOT_STARTED
POST_EBS_KD_HANDSHAKE      = NOT_TESTED
BCD_DEBUG_PATH_REACHED_EBS = NOT_OBSERVED
```

Do not repeat this BCD/KD variant.  Evidence:
`docs/PRODUCT_POST_EBS_BES_GATED_KD_RUNTIME_2026-09-10.md`.

## Linux ACPI-only control feasibility — 2026-09-10

Read-only inventory at that time found only the 168-byte direct AVF
serial-loopback payload; it bypasses UEFI, ACPI and any guest OS.  This was
later superseded by the acquired Debian control assets and by a forensic
recovery of an existing Termux/QEMU Windows experiment; do not treat the
following historical availability statement as current.

```text
LOCAL_LINUX_UEFI_ACPI_CONTROL_ASSET = NOT_AVAILABLE
LOCAL_QEMU_AARCH64_REFERENCE         = NOT_AVAILABLE
EXISTING_SERIAL_LOOPBACK_AS_ACPI_TEST = INVALID
```

Do not treat the loopback image as a Linux platform control. Evidence:
`docs/LINUX_ACPI_ONLY_REFERENCE_FEASIBILITY_2026-09-10.md`.

### Historical Termux/QEMU Windows control — 2026-09-13

Read-only recovery of the preserved August Termux/QEMU evidence established
that Windows 11 ARM64 Setup installed to NVMe and reached graphical OOBE on
the tablet.  The apparent later boot loop was the OOBE screen's required
network/update recovery, not a pre-kernel/platform loop.  The project already
contains an ISO-free QEMU user-mode-NAT OOBE launcher.  This proves an
independent TCG-QEMU Windows control only; it does not advance the separate
GenieZone/crosvm `WINDOWS_POST_EBS` boundary.

```text
QEMU_WINDOWS_SETUP_VISIBLE  = PASS (historical)
QEMU_WINDOWS_OOBE_USERMODE  = PASS (historical)
QEMU_PLATFORM_BOOT_LOOP     = REFUTED
AVF_WINDOWS_POST_EBS         = NOT_CONFIRMED
```

Evidence: `docs/HISTORICAL_QEMU_WINDOWS_25H2_CONTROL_2026-09-13.md`.

### Product 1-vCPU versus host-topology Windows A/B — 2026-09-13

The AVF product app was temporarily switched from its normal one-vCPU request
to the framework's host-topology request.  The system created an eight-vCPU
VM, and the FDT-derived ACPI table correctly enumerated GICC UID/MPIDR 0–7
with a 1-MiB GICR range.  Windows Boot Manager reached the established `ER`
post-`ExitBootServices()` boundary but emitted no later Windows/WinPE signal.
The immutable raw image rehashed exactly before and after cleanup, the
temporary VM was deleted, and the original APK was restored byte-for-byte.

```text
PRODUCT_8VCPU_FDT_ACPI_CONTRACT  = PASS
PRODUCT_8VCPU_EXIT_BOOT_SERVICES = PASS
PRODUCT_8VCPU_WINDOWS_POST_EBS   = NOT_CONFIRMED
SINGLE_VCPU_AS_FAST_WINDOWS_FIX  = REFUTED
```

Evidence: `docs/PRODUCT_8VCPU_WINDOWS_AB_RUNTIME_2026-09-13.md`.

### Product GIC ITS / IORT static audit — 2026-09-13

The exact one- and eight-vCPU MADT lengths account completely for GICC, GICD
and GICR records; neither contains a MADT GIC ITS record.  This is a valid
optional GICv3 feature omission.  Although the generic EDK2 source contains
an IORT ITS-group template, the actual product XSDT does not publish IORT, so
Windows cannot consume that template in the current boot.  An ITS-enable
experiment would fabricate hardware rather than repair a demonstrated
contract violation.

```text
PRODUCT_GIC_ITS_PRESENT             = NO
PRODUCT_IORT_PUBLISHED_TO_WINDOWS   = NO
GIC_ITS_AS_EARLY_WINDOWS_CAUSE      = NOT_PROVEN
FIRMWARE_ITS_ENABLE_A_B             = NOT_JUSTIFIED
```

Evidence: `docs/PRODUCT_GIC_ITS_IORT_STATIC_AUDIT_2026-09-13.md`.

### Debian ARM64 Linux ACPI control assets — 2026-09-11

After explicit approval, the official Debian Bookworm ARM64 netboot archive
was acquired and verified against Debian's manifest. It supplies standard
`grubaa64.efi`, kernel and initrd, with `acpi=force` and the known `ttyS0`
console specified in the checked-in GRUB configuration.  Candidate generation
requires an elevated Windows storage operation and has not yet been run.

```text
LINUX_ACPI_ONLY_CONTROL_ASSETS = VERIFIED
LINUX_ACPI_ONLY_CANDIDATE      = NOT_MATERIALIZED
LINUX_ACPI_ONLY_RUNTIME        = NOT_RUN
```

Entry point: `tools/linux-acpi-control/prepare-linux-acpi-control.ps1`.

## Direct Linux EFI-stub handoff probe — prepared 2026-09-11

The GRUB-based Debian control did not distinguish GRUB's kernel handoff from
Linux EFI-stub/kernel progress.  A separate, 20,480-byte ARM64 EFI launcher
has now been built and statically verified.  It emits `L0/L1/L2/L3/LX`, uses
UEFI `LoadImage`/`StartImage` directly on Debian's ARM64 Image, and embeds the
explicit initrd, ACPI and early-serial options.  This is a disposable media
launcher only; it is **not** embedded in firmware.

```text
LINUX_DIRECT_EFI_STUB_LAUNCHER_BUILD = PASS
LINUX_DIRECT_EFI_STUB_STATIC_AUDIT   = PASS
LINUX_DIRECT_EFI_STUB_CANDIDATE      = NOT_MATERIALIZED
LINUX_DIRECT_EFI_STUB_RUNTIME        = NOT_RUN
```

The elevated, standard-FAT-only offline entry point is
`tools/linux-efi-stub-control/prepare-linux-efi-stub-control.ps1`.  Do not
transfer or launch a candidate until it and its offline audit return
`RESULT=PASS`.  Details:
`docs/LINUX_EFI_STUB_HANDOFF_PROBE_2026-09-11.md`.

### Full AVF/GenieZone interface re-audit — 2026-09-14

A fresh read-only pass after the August security update revisited the app API,
shell `vm` CLI, AVF Binder, privileged Terminal APK, crosvm GDB, tracefs,
`/dev/gzvm`, Samsung HyPer HAL and guest-facing host devices. The only changed
whole artefact, `VmTerminalApp.apk`, has byte-identical `classes.dex`,
resources and manifest compared with the retained pre-OTA copy. The framework
jar remains byte-identical. No new public or app-usable guest-PC/vCPU/exit/IRQ
or timer observer was exposed.

```text
POST_OTA_NEW_DEBUG_INTERFACE          = NOT_OBSERVED
DIRECT_POST_EBS_WINDOWS_OBSERVABILITY = BLOCKED
```

This closes the "missed public interface" check for build `X736BXXS8BZH4`;
it does not prohibit productive pre-EBS product work or a vendor-provided
diagnostic path. Details: `docs/FULL_AVF_INTERFACE_REAUDIT_2026-09-14.md`.

### Direct Linux EFI-stub v2 runtime — 2026-09-11

The corrected v2 raw image was produced only after a VHD detach/re-attach
flush boundary, then audited and reconstructed by a 26-range transaction
overlay.  One 100-second app-owned run loaded the expected `0x5000` direct
launcher, loaded the Debian Image (`0x2010000`), emitted `L0/L1/L2/L3`, and
the official EFI stub printed `Exiting boot services...` immediately before
the proven post-return firmware marker `ER`.  There was no Linux earlycon or
`Linux version` line during the remaining capture window.

```text
LINUX_DIRECT_EFI_STUB_LOADED            = PASS
LINUX_DIRECT_EFI_STUB_STARTIMAGE         = PASS
LINUX_EFI_STUB_EBS_RETURN                = PASS
LINUX_KERNEL_EARLY_SERIAL                = NOT_OBSERVED
COMMON_OS_POST_EBS_SERIAL_SILENCE        = OBSERVED
IMMUTABLE_BASELINE_RESTORED              = PASS
```

This removes both GRUB and Windows Setup/WinPE as required explanations for
the silence, but does not directly prove or disprove native Linux-kernel
instruction entry.  Do not retry media variants without a new concrete shared
post-EBS observer/hypothesis.  Evidence:
`docs/LINUX_EFI_STUB_HANDOFF_PROBE_2026-09-11.md` and
`build-logs/linux-efi-stub-runtime-v2-20260911-173721/`.

### Direct Linux EFI-stub v1 transport finding — 2026-09-11

The first direct-stub runtime must be discarded as a candidate-transport
failure, not interpreted as Linux silence.  The transactional app path
accepted then rolled back the v1 patch exactly, but raw serial loaded an old
`BOOTAA64.EFI` of `0x2DB000` bytes and did not contain `L0`; the new launcher
is `0x5000` bytes.  The v1 materializer copied raw sectors immediately after
filesystem writes, without a detach/re-attach flush of the VHD cache.

```text
LINUX_DIRECT_EFI_STUB_V1_RUNTIME = INVALID_RAW_TRANSPORT
LINUX_DIRECT_EFI_STUB_RUNTIME    = NOT_RUN
IMMUTABLE_BASELINE_RESTORED      = PASS
```

The only permitted correction is the prepared v2 materialization script:
`tools/linux-efi-stub-control/prepare-linux-efi-stub-control-v2.ps1`.  It
forces a VHD detach/re-attach before sector-for-sector raw extraction and uses
new output names.  No second runtime is permitted until its offline gates and
new delta overlay pass.  Details:
`docs/LINUX_EFI_STUB_HANDOFF_PROBE_2026-09-11.md`.

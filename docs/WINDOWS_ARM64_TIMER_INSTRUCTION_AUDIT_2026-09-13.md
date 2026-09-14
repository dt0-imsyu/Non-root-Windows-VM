# Windows ARM64 timer instruction audit — 2026-09-13

## Purpose

P2–P5 prove that the product VM loses non-secure EL1 physical comparator state
after the EBS / guest handoff.  This audit asks the separate causal question:
does the exact Windows ARM64 WinPE image ever program that physical comparator?

This was read-only.  It did not start a VM or alter firmware, WIM, BCD,
Android, ACPI, or the immutable runtime image.

## Inputs

The following files were extracted read-only from index 2 of the immutable
baseline `boot.wim`:

| File | Windows version | SHA-256 |
|---|---:|---|
| `ntoskrnl.exe` | `10.0.26100.6584` | `C667739004D1186DACA2FD3FE7CCDE61394BC068F385B4BB8CD5364D3005A734` |
| `winload.efi` | `10.0.26100.6584` | `F7747F4AC18CCD66EBF6A043D979CF30C7731114C27C33FF2FC3C0610F491D31` |
| `hal.dll` | `10.0.26100.1` | `C73030EF5F506B2EBEAB30B2BD658EC56519D5CD45FD96481084BF3E8EF4EBC6` |

The source WIM remains:

```text
baseline boot.wim SHA-256 = A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4
```

`aarch64-none-elf-objdump` disassembled each complete PE image.  A second
independent scan counted system-register instruction encodings while masking
the destination/source general-purpose register bits.

## Exact instruction results

| Image | `MRS CNTVCT` | `MRS CNTPCT` | `MSR CNTV_CVAL` | `MSR CNTV_CTL` | `MSR CNTP_CVAL` | `MSR CNTP_CTL` | `MSR CNTP_TVAL` |
|---|---:|---:|---:|---:|---:|---:|---:|
| `ntoskrnl.exe` | 14 | 3 | 2 | 1 | 0 | 0 | 0 |
| `winload.efi` | 26 | 0 | 0 | 0 | 0 | 0 | 0 |
| `hal.dll` | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

The kernel's concrete timer path contains, among others:

```text
0x140213964  MSR CNTV_CVAL_EL0, x10
0x140213a38  MRS CNTVCT_EL0
0x140213b24  MSR CNTV_CVAL_EL0, x1
0x1404a1fe8  MSR CNTV_CTL_EL0, x9
```

The complete disassembly contains no instruction encoding for a guest
`CNTP_CVAL_EL0`, `CNTP_CTL_EL0`, or `CNTP_TVAL_EL0` write.  This is stronger
than a symbol-name inference: direct AArch64 system-register access has a
fixed instruction encoding, so ordinary kernel code cannot arm the physical
comparator without one of these instructions.

`CNTPCT_EL0` reads remain present.  They are reads of the physical counter,
not writes to the physical comparator state that P4/P5 showed is defective.

## Interpretation

```text
WINDOWS_ARM64_VIRTUAL_TIMER_CODE_PATH = PASS (static)
WINDOWS_PHYSICAL_TIMER_DIRECT_CAUSE   = REFUTED_FOR_CURRENT_WINPE_BUILD
```

The current Windows build does use the architectural virtual timer code path.
Consequently, the P2–P5 `CNTP_*` comparator defect is a real platform contract
violation and remains appropriate vendor evidence, but it is not the direct
timer-comparator explanation for this Windows post-EBS stall.

This does not prove which exact virtual-timer instruction executes before the
observed hang, nor does it reveal the current PC.  It only closes the prior
physical-timer causal hypothesis for this exact kernel, preventing an invalid
GTDT/PPI30 workaround.

## Source context

- [Microsoft: generic timer system counter on Arm](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps)
- [ACPI GTDT specification](https://uefi.org/specs/ACPI/6.6/05_ACPI_Software_Programming_Model/ACPI_Software_Programming_Model.html)
- [Arm Generic Timer guide](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Learn%20the%20Architecture/Generic%20Timer.pdf?revision=c710e7a7-9f52-4901-8c9d-91b19f44f9c7)

## Next boundary

Do not change GTDT to hide or remap PPI30: that would not affect the Windows
virtual comparator path.  The next highest-value hypothesis must target a
different Windows/GenieZone post-EBS contract, with a static basis before any
new runtime.

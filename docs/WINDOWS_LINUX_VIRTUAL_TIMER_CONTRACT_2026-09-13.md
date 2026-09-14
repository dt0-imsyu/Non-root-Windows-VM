# Windows/Linux virtual-timer contract — 2026-09-13

## Purpose

This is a derived compatibility milestone, not a claim that Windows has
started. It joins three independently retained facts about the same product
VM topology and the exact unmodified Windows 11 ARM64 WinPE kernel.

## Evidence chain

| Layer | Evidence | Result |
| --- | --- | --- |
| Product post-EBS platform | P1 armed `CNTV_TVAL_EL0`, enabled virtual PPI27, executed `WFI`, took/EOI'd PPI27, and resumed (`T0 -> T1 -> T2 -> T3 -> TR`). | PASS |
| Exact Windows 11 26100.6584 kernel | ARM64 instruction audit found `MSR CNTV_CVAL_EL0` twice and `MSR CNTV_CTL_EL0` once; it found no physical-comparator write. | Windows uses the virtual timer interface in its code path. |
| Linux ACPI control | The same product topology logged `arch_timer: cp15 timer(s) running at 13.00MHz (virt).` and reached installer userland. | PASS |

P1 is documented in
`docs/SYNTHETIC_POST_EBS_P1_RUNTIME_2026-09-10.md`; its PPI27 handler record
is a real delivery/wakeup result, not a register-only check. The Windows
instruction offsets are `0x140213964`, `0x140213b24` (`CNTV_CVAL_EL0`) and
`0x1404a1fe8` (`CNTV_CTL_EL0`) in the retained exact `ntoskrnl.exe` SHA-256
`C667739004D1186DACA2FD3FE7CCDE61394BC068F385B4BB8CD5364D3005A734`.

## Result

```text
POST_EBS_VIRTUAL_TIMER_PPI27          = PASS
LINUX_ACPI_VIRTUAL_TIMER_RUNTIME      = PASS
WINDOWS_ARM64_VIRTUAL_TIMER_CODE_PATH = PASS (static)
WINDOWS_LINUX_VIRTUAL_TIMER_CONTRACT  = PASS
```

The conclusion is intentionally limited: the product supplies the virtual
architectural timer interface selected by Linux and implemented by the exact
Windows kernel; physical CNTP/PPI30 remains an independent broken advertised
interface but is not the direct comparator path in this WinPE image.

This does **not** prove that Windows has reached its timer-initialization
instructions, and it does not make `WINDOWS_KERNEL_ENTRY` pass. It does remove
the virtual timer/PPI27 contract itself as a reason to keep changing GTDT,
GIC, or timer delivery.

## Consequence

No new timer firmware A/B is justified. The first remaining Windows-specific
diagnostic must observe execution/failure with known semantics; it should not
retest virtual-timer plumbing already covered by P1, Linux and the exact
Windows code audit.

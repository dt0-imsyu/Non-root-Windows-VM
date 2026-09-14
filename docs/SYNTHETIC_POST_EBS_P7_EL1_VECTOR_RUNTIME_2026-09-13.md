# Synthetic post-EBS P7 — EL1 exception-vector boundary

## Question

After the real Windows-loader `ExitBootServices()` return, can the product VM
temporarily replace its EL1 exception vector, take a synchronous exception,
return with `ERET`, and then continue through the already-proven virtual-timer
and reset path?

This is a firmware-only platform probe.  It changes no Windows media, BCD,
ACPI table, Android code, driver, or VM topology.

## Exact probe

P7 emits `X0`, saves `VBAR_EL1`, installs a probe-owned 2 KiB-aligned vector
table, executes one `BRK #0x714`, and restores the saved `VBAR_EL1` after the
handler returns.  The common handler:

1. advances `ELR_EL1` by four bytes to skip the BRK;
2. sets `gProbeVectorFired` with only `x16`/`x17` scratch registers; and
3. executes `ERET`.

Ordinary post-return C code emits `XV` when that flag is set, otherwise `XF`.
It then uses the existing P1 virtual-timer/GIC re-arm and reset path.  No
allocation, Boot Service, protocol, formatted logging, MMU, GIC, or timer
configuration change is made by the vector test itself.

Static AArch64 disassembly of the built probe shows the call to
`ProbeInstallAndTriggerVector`, `MRS/MSR VBAR_EL1`, `BRK #0x714`, `ERET`, and
the `VBAR_EL1` restore.  The vector target is `0x3800`, which is 2 KiB aligned.

## Offline artifacts

| Item | Value |
|---|---|
| P7 FD | `build-logs/synthetic-post-ebs-p7-el1-vector-20260913/KVMTOOL_EFI-p7-el1-vector.fd` |
| FD SHA-256 | `CE5E35F34A713CA836B11B33570FB78C5021C2333B9C8F0604941AAA368AF717` |
| Firmware range | offset `7250927616`, length `2097152` bytes |
| Reversible patch SHA-256 | `467D139E1BD9B24937B061C678777B636B1B65BBA0340FFFFF99036B13927241` |
| Patch size | `4194436` bytes, including the original 2 MiB rollback payload |

The temporary DSC diagnostic define was removed immediately after the FD and
patch were captured; the source tree is back to its normal compiler flag.

## One bounded product runtime

The runner checked the immutable product image before apply, launched one
60-second product VM, force-stopped it, pulled raw serial, requested rollback,
and rechecked the baseline.

```text
BASELINE_BEFORE_SHA256 = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
PATCH_STAGED_SHA256    = 467D139E1BD9B24937B061C678777B636B1B65BBA0340FFFFF99036B13927241
RAW TERMINAL MARKERS   = BES X0 XV T0 T1 T2 T3 TR
ROLLBACK_BASELINE_SHA256 = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
RESULT = PASS
```

`BES` is the established marker written after the original
`ExitBootServices()` returned successfully.  `X0 -> XV` proves the EL1 vector
install, synchronous exception delivery, flag store, adjusted `ELR_EL1`, and
`ERET` return all completed after that boundary.  `T0 -> T1 -> T2 -> T3 -> TR`
then independently proves the previously established virtual timer/GIC/reset
path remained usable.

Raw evidence:
`build-logs/synthetic-post-ebs-p7-el1-vector-runtime-20260913-retry/raw-serial.log`
(SHA-256 `FB5AF25D77F708A780007A16BAB395279B405B902BBB34F8D74BE0AFEDC403D3`).

## Verdict

```text
POST_EBS_EL1_EXCEPTION_VECTOR = PASS
POST_EBS_EL1_SYNC_EXCEPTION   = PASS
POST_EBS_EL1_ERET_RETURN       = PASS
PRODUCT_BASELINE_RESTORED      = PASS
```

This establishes a live post-EBS EL1 exception/return boundary for the product
platform.  It does not prove that Windows reaches or configures its own vector
table; it removes a firmware-side EL1 exception delivery/ERET failure as a
generic explanation for the current Windows stall.

The next useful work should be a source-level comparison of the exact Windows
early EL1 setup with the now-proven primitive boundaries, not another random
firmware-state mutation.

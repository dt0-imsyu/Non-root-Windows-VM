# Shell r11 baseline-BCD control — 2026-09-08

## Scope

One bounded, disposable shell-owned AVF VM run was used only to decide whether
the preceding r11 shell KD result failed before `ExitBootServices` because of
its KD BCD configuration, or because the shell VM itself diverges from the
product runtime.  The run used the same r11 firmware range and the same
one-vCPU/4-GiB shell VM shape, but used the separately preserved baseline BCD.

No Android product image, WIM, BCD in the product image, Windows binary,
driver, firmware source, or app was changed.

## Inputs verified before launch

| Item | Value |
|---|---|
| Product baseline SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| Disposable clone | `E:\winavf-kd-shell-clone-20260907-baseline.img` |
| Clone size | `9,126,805,504` bytes |
| Clone BCD SHA-256 | `DE6698BF9CCF5205403A5E8ED1D6CC5E2790A3E3EF23F4539B512D1C0DFB9A11` |
| `BOOTAA64.EFI` SHA-256 | `EFCC88441775A1ECEF644E05A52D7A01DC98388EA4426F133B9132CBE1483A19` |
| r11 patch SHA-256 | `0D78B91BDA1B2C3EB241CF8B1D731280DB511958B3B196662046C76AF7E8364E` |
| Applied range | offset `7250927616`, length `2097152` |
| Applied range SHA-256 | `9ED3DD035116A39FEAC7C79A9C0C9AC640EA222D499A8EC3B1C6FCEE1ADFE72F` |
| Remote staged clone SHA-256 | `EE0206AAA37AB96B6FA7FBD01D3D22FB23B72C6D82708A4359A110F684CABBCE` |

The clone’s BCD and `BOOTAA64.EFI` were read through its FAT ESP after the
firmware-range operation.  They remained exactly the control BCD and the
previously audited boot manager, respectively.

## One runtime

The shell VM was CID `2115`, used r11, `ttyS0`, one CPU, and 4096 MiB.  It
ran with a 100-second timeout and without `--console-in`, bridge, KD endpoint,
or KD BCD candidate.  The process timed out as expected (`VM_EXIT=124`);
afterward `vm list` was empty.

Artifacts are in
`Non-root-Windows-VM/build-logs/shell-windows-r11-bcd-control-20260908/device/`:

| Artifact | SHA-256 / observation |
|---|---|
| `raw-serial.bin` | `71F55E8F70DC057770FA0526F5AE2C103DB23BCF2C1971FE7D412B7A480551D4`, 32,528 bytes |
| `vm.stdout-stderr.log` | `FF25688AA0C74E4F8C3E177216DADFD0AA90BA608621E8BC85DAF0189132D097` |
| `crosvm.log` | empty |
| serial `AVF_BDS_START_IMAGE` | observed at byte offset 9220 |
| serial `Loading files...` | observed at byte offset 10247 |
| serial `BES` / `EBS_AUDIT` / `VA0` / `VA1` | not observed |

The control UART transcript is not byte-identical to the earlier KD transcript
(first difference at byte 2767), but it has the same 32,528-byte bounded
pre-EBS outcome: repeated Windows Boot Manager progress and no `BES`.

## Cleanup and conclusion

The designated local clone range was rolled back, verifying
`9ED3...FE72 -> 3DAF5427A9023BFE8D4044932D4020364021BC942A33DF77006FC1536479F995`.
The exact remote staging directory, including the 9-GB clone, was removed;
no shell VMs remained.  The Android product baseline was independently
rehashed after cleanup and exactly matched `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

```text
SHELL_R11_BASELINE_BCD_CONTROL = COMPLETE
SHELL_EBS_CONTROL              = NOT_OBSERVED
SHELL_KD_BCD_CAUSES_PRE_EBS_DIVERGENCE = NO
SHELL_VM_TOPOLOGY_EQUIVALENT   = NO (at the EBS boundary)
WINDOWS_KD_HANDSHAKE            = NOT_OBSERVED / non-diagnostic for product post-EBS
```

No further blind KD, serial, or BCD variants are justified on this shell clone.
Any direct post-EBS diagnosis now requires a target that demonstrably reaches
the product EBS boundary, or a vendor-privileged VMM/GZVM guest-state observer.

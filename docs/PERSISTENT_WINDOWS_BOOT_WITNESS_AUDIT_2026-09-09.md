# Persistent Windows boot-witness audit — 2026-09-09

## Scope and guardrail

This audit replaces the closed direct KD/GDB branch with a persistent,
post-stop witness.  It does **not** reopen BCD, KD, GDB, firmware, WIM,
driver, or AVF transport work.  No VM was launched while this audit selected
and statically verified the candidate.

The target is the immutable app-owned product medium:

```text
E:\winavf-a3-append-only-runtime.img
SHA-256 = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
bytes   = 9,126,805,504
```

Its only GPT partition is GPT entry 1, a FAT32 EFI System Partition:

```text
first LBA  = 2048
offset     = 1,048,576 bytes
size       = 9,125,740,032 bytes
type GUID  = c12a7328-f81f-11d2-ba4b-00a0c93ec93b
```

The exact unmodified `\SOURCES\BOOT.WIM` extracted from that medium is:

```text
bytes   = 623,400,308
SHA-256 = A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4
index 2 = Microsoft Windows Setup (arm64), WindowsPE, build 26100.6584
```

## Candidate audit

| Artifact | Earliest semantics | Persistence in this RAM-disk WinPE | Result |
|---|---|---|---|
| `%SystemRoot%\Bootstat.dat` | Boot/shutdown/recovery lifecycle bookkeeping; not an exact kernel-entry signal. | **No**: the documented path is under `%SystemRoot%`; this target's OS is WIM RAM-disk `X:`. It is absent from both persistent FAT and the immutable WIM. | Rejected. |
| `Ntbtlog.txt` | Kernel initialization driver-load list, if enabled. | **No**: it is written under `%WINDIR%`, therefore this target's volatile `X:`. It also requires the now-closed BCD `bootlog` setting. | Rejected. |
| Event log / registry changes | EventLog service or later service/configuration activity. | **No by default**: EventLog defaults to `%SystemRoot%\System32\winevt\Logs`; index 2 has an empty `winevt\Logs` directory. SYSTEM changes are copy-on-write in the RAM-disk WIM. | Rejected as a default witness. |
| Crash dump / minidump | A deliberate or incidental bugcheck reached dump handling. | Not a normal early-boot witness; dump setup is consumed by SMSS and requires dump storage/page-file prerequisites not present on this FAT32 RAM-disk boot media. | Rejected. |
| Setup `LogPath` through standard `Autounattend.xml` | Microsoft Windows Setup executed the `windowsPE` configuration pass. This is necessarily after NT kernel execution, though it is intentionally **not** an exact kernel-entry claim. | **Yes when redirected**: `LogPath` is documented to require a local fixed-disk path. The only existing FAT ESP can be assigned `C:` in the same `windowsPE` pass without wipe/format, then Setup can write `C:\SETUPACT.LOG` / `C:\SETUPERR.LOG`. | **Selected.** |

The Windows documentation supplies the essential semantics:

- [`bootlog`](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--set) writes `Ntbtlog.txt` under `%WINDIR%`.
- [`Bootstat.dat`](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/event-id-41-restart) records lifecycle success/failure stages, not an exact entry marker.
- [WinPE runs directly from memory](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-intro?view=windows-11); its scratch/filesystem drive is `X:`.
- [`Microsoft-Windows-Setup/LogPath`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-logpath) is for the `windowsPE` configuration pass and requires a fully qualified path on a local fixed disk.
- [`ModifyPartition/Letter`](https://learn.microsoft.com/en-us/Windows-hardware/customize/desktop/unattend/microsoft-windows-setup-diskconfiguration-disk-modifypartitions-modifypartition-letter) is valid in `windowsPE`; [`WillWipeDisk=false`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-diskconfiguration-disk-willwipedisk) explicitly prevents erase/format.
- Windows Setup searches for `Autounattend.xml` at the root of boot media when no other answer file was selected ([Microsoft documentation](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup?view=windows-11)).

## Selected disposable test

`tools/persistent-boot-witness/Autounattend.xml` is the sole semantic media
change. It adds no executable or driver, does not change BCD or WIM, does not
format/repartition, and requests only:

```text
Disk 0 / partition 1: assign C:
WillWipeDisk: false
Setup LogPath: C:\
```

Therefore any **new, nonempty** root `SETUPACT.LOG` or `SETUPERR.LOG` on the
stopped clone is a durable standard-Windows witness:

```text
PERSISTENT_WINDOWS_SETUP_WITNESS = PASS
WINDOWS_KERNEL_EXECUTION_AFTER_EBS = PASS
```

It proves that Windows Setup began the WindowsPE configuration pass, and hence
that the kernel executed after the independently proven EBS return. It does
not identify the first `ntoskrnl` instruction or establish SMSS/startnet.

If neither log appears, the only valid classification is:

```text
PERSISTENT_WINDOWS_SETUP_WITNESS = NOT_OBSERVED
WINDOWS_KERNEL_EXECUTION_AFTER_EBS = NOT_OBSERVED
```

That negative result does **not** prove that the kernel did not execute. It
can also mean that the machine stopped before Setup configured the fixed
volume or its log path.

## Exact inspection and rollback procedure

1. `materialize-persistent-witness-candidate.ps1` copies the immutable raw
   baseline to a new file, asserts that the witness does not already exist,
   then writes and reads back only `\Autounattend.xml` with the trusted mtools
   FAT implementation.
2. `new-raw-transactional-delta.ps1` creates a reversible `WAVFPAT1` bundle
   and proves the overlay reconstructs the candidate SHA exactly.
3. The app verifies the immutable Android external baseline hash before it
   applies the bundle to its **private clone**. The clone is the sole writable
   guest disk.
4. After one bounded VM interval, the runner force-stops the app/VM. A new
   app-side offline reader opens only the stopped private clone, extracts the
   root Setup log(s), and writes their bytes/SHA to app-external evidence.
5. The app deletes that private clone and active patch record rather than
   attempting range rollback over guest-generated FAT writes. It then hashes
   the immutable external baseline again. That deletion is the rollback.

The host-side post-stop fallback inspector is
`tools/persistent-boot-witness/inspect-persistent-witness.ps1`; it uses mtools
read-only operations on any exported clone and applies the same positive-only
classification.

## One bounded runtime — result

The candidate was statically materialized and transactionally validated before
the single run:

```text
candidate SHA-256 = 01AB0423E325F0574755349B6104D11B18D275BA81824AD175985DBBFF860281
patch SHA-256     = 205C8347A4379E92D8C031C52829614516EC9A1EC8465EA7F735CF5F2AF9F371
patch bytes       = 33,554,792
ranges            = 4 x 4 MiB
overlay rollback  = PASS
```

Exactly one app-owned product-equivalent VM ran for 100 seconds. Its raw serial
capture (`SHA-256 619500F9B395654341665844A1AAEB0CB4CF3FE81A8919B5ED284EDC6A1D0242`,
10,367 bytes) ends at the known `ER` post-`ExitBootServices()` return boundary.
No second VM was started.

After force-stopping the VM, the app opened the stopped private clone read-only:

```text
stopped-clone SHA-256 = 01AB0423E325F0574755349B6104D11B18D275BA81824AD175985DBBFF860281
SETUPACT.LOG          = absent
SETUPERR.LOG          = absent
PERSISTENT_WINDOWS_SETUP_WITNESS = NOT_OBSERVED
WINDOWS_KERNEL_EXECUTION_AFTER_EBS = NOT_OBSERVED
```

The stopped clone's exact equality with the pre-run candidate establishes that
the guest did not persist any sector write to the FAT disk during the bounded
interval. It does not prove that Windows did not execute kernel instructions:
the selected Setup witness is only written later, after Windows Setup begins
its `windowsPE` configuration pass and has configured the persistent volume.

Rollback was deletion of the app-private disposable clone and its active patch
record, not a range rollback over possible guest writes. It passed; no VM
remained and the immutable external Android image rehashed exactly to the
baseline SHA. The temporary hidden-API setting was also restored to `null`.

The host-side candidate file remains only as a local, never-staged static
reproduction artifact; it is not the Android runtime clone and was never
written by the guest. Device rollback is complete.

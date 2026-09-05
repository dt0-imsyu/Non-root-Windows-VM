# WinAVF handoff — 2026-09-05

## Current confirmed state

```
EXIT_BOOT_SERVICES_RETURN = PASS
MODIFIED_WIM_EBS          = PASS
MODIFIED_WIM_TRANSPORT    = PASS
```

The app-private tablet runtime image has been rolled back after the successful
modified-WIM test.  The rollback UI reported: `Small image patch rolled back
and the runtime image was verified.` No active patch record remains.

## Immutable baseline

* Raw image: `C:\Users\denis\MainProjects\win11ontab\handoff-compact-2026-08-23\handoff-compact-2026-08-23\windows-headless-media\win11-gop-ebs-r1.img`
* Size: `9,126,805,504` bytes
* SHA-256: `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`
* FAT32 partition offset: `1,048,576`; cluster size: `8,192` bytes.

The Android transactional patch path validates the complete baseline SHA-256
before a forward write, verifies every range before/after writing, and verifies
the full immutable SHA-256 after rollback.

## Completed harmless FAT-grow A/B

Only boot.wim index 2 changed, by adding `\WinAvf\probe.txt`.  No driver,
SYSTEM hive, service, BCD, testsigning, firmware, GOP, ACPI, SMBIOS, or CPU
topology change was made.

Modified WIM:

* `build-logs\wim-fat-grow-a-20260904\boot-wim-harmless-fat-grow.wim`
* Size: `624,978,413` bytes
* SHA-256: `AC58474DF991875924C10C912A06E54521F42AF17B5EDA30F9D0DEA8F27C64A9`
* `wimlib-imagex verify`: PASS; index 2 and `\WinAvf\probe.txt`: PASS.

The original builder defect was an omitted bridge from the old BOOT.WIM tail
to the free appended extent. It is now explicitly emitted into both FAT copies
and asserted before patch serialization.

```
start cluster = 6838 (unchanged)
old chain     = 76099 clusters
new chain     = 76292 clusters
old tail      = 82936
new extent    = 2679..2871 (193 clusters; non-contiguous)
FAT1/FAT2 bridge 82936 -> 2679 = PASS
new tail 2871 -> EOC           = PASS
```

Final transactional patch:

* `build-logs\wim-fat-grow-a-20260904\harmless-wim-fat-grow-preflight-pass.patch`
* format `WAVFPAT1`; 9 ranges; `3,187,430` bytes
* SHA-256: `914435AC1C667ED8EE8DC46BDCEA769F0A5A081E83C8A21BEF0ED67CD85BE3F5`

Read-only audit:

```
ForwardWimSha256   = AC58474DF991875924C10C912A06E54521F42AF17B5EDA30F9D0DEA8F27C64A9
RollbackWimSha256  = A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4
Fat1Fat2           = PASS
DirectoryInvariant = PASS
RollbackSimulation = PASS
Result             = PASS
```

The corresponding local audit log is
`build-logs\wim-fat-grow-a-20260904\audit-preflight-pass.stdout.log`.

## Runtime proof

The harmless patch was staged and accepted after the app's baseline verification.
One VM run reached the stable final raw serial marker `ER`, without reset.
`E` is the existing ExitBootServices event marker; `R` is emitted after the
real original `ExitBootServices()` returns. This is the same proven return
boundary as the immutable baseline.

Full local serial log:
`build-logs\wim-fat-grow-a-20260904\runtime-harmless-fat-grow-serial.log`.

## Local tools to retain

* `tools\new-winavf-fat-grow-patch.ps1`: read-only baseline, reversible
  WAVFPAT1 generation, explicit non-contiguous bridge in FAT1/FAT2, and
  in-memory preflight of chain, EOC, reachability, directory invariant and WIM SHA.
* `tools\audit-winavf-fat-grow-patch.ps1`: read-only serialized-patch audit of
  range hashes, base SHA, FAT copies, bridge, forward WIM SHA and rollback SHA.

Earlier invalid 7-range patches in the build-log folder are diagnostic only;
they were never staged to the tablet.

## Next test: TEST B

Use a fresh immutable baseline and the proven FAT-grow/transactional route.
Add only ARM64 `probe.sys` to boot.wim index 2 and the necessary `BOOT_START`
service registration in the offline SYSTEM hive. Start without BCD or
testsigning changes. Require the identical full offline audit before staging.

If modified media no longer reaches the proven EBS-return marker, stop and
separate driver acceptance/Code Integrity from DriverEntry; do not change
firmware, BCD, testsigning, GOP, ACPI, or generic FAT allocation without new
evidence.

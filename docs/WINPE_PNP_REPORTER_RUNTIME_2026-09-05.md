# WinPE PnP reporter runtime — 2026-09-05

## Scope

This was one controlled user-mode observation run.  It did not alter firmware,
EDK2, BCD, test-signing, ACPI, GOP, PCI topology, or the production-signed
`viogpudo.sys` and `viosock.sys` files.

`SIGNED_RAW_UART_PNP_MARKER = BLOCKED` remains closed: direct signed-driver
UART instrumentation is incompatible with preserving the WHCP catalog chain.

## Reporter

The reporter is a CRT-free ARM64 native console executable using SetupAPI and
Configuration Manager state through SetupAPI.  It reports present devnodes for
the exact observed IDs `PCI\\VEN_1AF4&DEV_1050` and
`PCI\\VEN_1AF4&DEV_1053`, the actual service property, CM status/problem, and
`DN_STARTED`.  It treats a matching service on the devnode as `DRIVER_BOUND`;
it never treats DriverStore presence as binding.

After `wpeinit`, it searches volumes by label `WINSETUP` plus filesystem
`FAT32`, explicitly rejects `X:`, writes `\\WinAvf\\pnp-report.txt`, then
atomically publishes the same report as root `\\WINPE.TXT`.  The already
installed Android launcher observes root `WINPE.TXT` and exports it as a
userland marker.  `wpeutil reboot` follows the reporter, giving a second
independent expected effect.

Reporter SHA-256:

```text
1A5C4DF523396A2E5A02CEC5C0862D7015D94C43CE90694432C951D8D6799EA7
```

Static checks passed:

- PE: ARM64, Windows CUI.
- Imports: `KERNEL32.dll`, `SETUPAPI.dll` only.
- Both imports exist in target WinPE.
- `wimlib verify = PASS`.

## Media and transactional patch

Preserved graphics candidate, unchanged:

```text
627999710 bytes
7E423FD9E6885C12E0D7C5FC70E7D0B1FEF32C4D275EE79E32CFCDA7985141E7
```

Reporter WIM:

```text
629584824 bytes
8A23DE5EA981800DF089E43EB8AC42FD576CF5E2E6E102B17795B89D7436B7CD
```

The append-only WIM update changed only `\\WinAvf\\WinAvfPnpReporter.exe` and
`\\Windows\\System32\\startnet.cmd`.  Extracted `viogpudo.sys` and
`viosock.sys` hashes match their pre-reporter candidate copies.

Transactional patch:

```text
12409548 bytes, 13 ranges
2C1CE4632C131E40FC4584BB89DCAFD34C08E3BEFC28E959D500BB5177A62572
```

Offline audit against immutable baseline
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`:

```text
OldTail=82936
FirstNewCluster=882627
OldClusters=76099
NewClusters=76854
FAT1/FAT2=PASS
DirectoryInvariant=PASS
ForwardWimSha256=8A23DE5EA981800DF089E43EB8AC42FD576CF5E2E6E102B17795B89D7436B7CD
RollbackWimSha256=A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4
RollbackSimulation=PASS
```

## One runtime result

The device baseline hash matched before patch application.  The patch SHA was
verified after staging.  One VM run was launched.

The saved serial log is
`build-logs/graphics-poc-20260905/pnp-reporter-runtime-serial.log`, SHA-256
`8A3248A8C7DE99C2CF3015422A68A577F741DF7F44CB515578E61A684A2765BF`.
It reaches Windows Boot Manager and terminates at the existing raw `ER`
boundary.  It never produced `WINPE.TXT`, the Android-exported userland marker,
or a reboot.

Therefore:

```text
WINPE_USERLAND = NOT_CONFIRMED
WINPE_VIOGPU_BOUND = NOT_TESTED
WINPE_VIOGPU_STARTED = NOT_TESTED
WINPE_VSOCK_BOUND = NOT_TESTED
WINPE_VSOCK_STARTED = NOT_TESTED
```

This does not classify either driver as rejected, unbound, or failed: the
reporter itself was never observed.

## Rollback

The app's transactional rollback was invoked immediately after the one run.
Its visible completion status was:

```text
Small image patch rolled back and the runtime image was verified.
```

No additional WIM or driver variants were tried.

## Single cheapest next test

Prove whether `startnet.cmd` is reached independently of post-`wpeinit` PnP:
use a tiny persistent-volume marker before `wpeinit`, without any driver,
firmware, BCD, or graphics change.  Only if that marker appears should the
PnP reporter be moved forward to distinguish `wpeinit` from PnP state.

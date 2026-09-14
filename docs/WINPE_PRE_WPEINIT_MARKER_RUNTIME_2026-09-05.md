# WinPE pre-`wpeinit` persistent-marker runtime — 2026-09-05

## Scope

This was one controlled test to distinguish a potential `startnet.cmd` entry
from work inside `wpeinit`.  It did not change firmware, EDK2, BCD,
test-signing, ACPI, GOP, PCI topology, `viogpudo.sys`, `viosock.sys`, or the
PnP reporter.

The source was the preserved graphics candidate, not the earlier PnP reporter
WIM.  In index 2, the only changes were a small executable and
`startnet.cmd`:

```bat
\WinAvf\WinAvfPreWpeinitMarker.exe
wpeinit
wpeutil reboot
```

## Marker

`WinAvfPreWpeinitMarker.exe` is a 3,584-byte CRT-free ARM64 PE, SHA-256:

```text
B2F9CD593E5B5DBF83C1CBAC0D3CE85DF7915BE518C9437F5075201D522BCF0F
```

It imports only `KERNEL32.dll`.  It enumerates volumes by label `WINSETUP`
and filesystem `FAT32`, rejects `X:`, and before `wpeinit` attempts to write:

```text
\WinAvf\pre-wpeinit-pass.txt
\WINPE.TXT
```

The root marker contains `stage=WINPE_USERLAND_PRE_WPEINIT`; the installed
launcher recognizes and exports that marker.  A subsequent `wpeutil reboot`
is the independent expected effect.

## Offline media and patch

WIM:

```text
629583629 bytes
7C305B8E031E980EA7C87550EE1D8400C71F3F45D318C0E1AE63173733CCE320
wimlib verify = PASS
```

Transactional patch:

```text
12407158 bytes, 13 ranges
57FF135345304560EC0756AD8497B6E633EB25FFBB77F553EFEA516A8BBC7464
```

The audit against immutable baseline
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`
passed:

```text
OldTail=82936
FirstNewCluster=882627
OldClusters=76099
NewClusters=76854
ForwardWimSha256=7C305B8E031E980EA7C87550EE1D8400C71F3F45D318C0E1AE63173733CCE320
RollbackWimSha256=A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4
FAT1/FAT2=PASS
DirectoryInvariant=PASS
RollbackSimulation=PASS
```

## One runtime result

The device baseline hash matched before staging.  The staged patch hash
matched the local patch.  Exactly one VM run was launched.

No exported `winpe-userland-marker.txt`, root `WINPE.TXT`, or reboot appeared.
The serial log is
`build-logs/graphics-poc-20260905/pre-wpeinit-marker-runtime-serial.log`,
10,369 bytes, SHA-256
`BCD8318269495EDA1D29313B2252DD2F0758B6E6F8C3BDE8C2DDA24225B661D6`.
It ends at the existing raw `ER` boundary.

Therefore:

```text
STARTNET_PRE_WPEINIT = NOT_CONFIRMED
WPEINIT_COMPLETION = NOT_CONFIRMED
WINPE_USERLAND = NOT_CONFIRMED
```

This is not proof that `startnet.cmd` was not entered: the persistent
`WINSETUP` FAT32 volume may have been unavailable or unwritable before
`wpeinit`.  It also gives no new result for viogpu or viosock binding.

## Rollback

The patch was rolled back immediately.  The installed app displayed:

```text
Small image patch rolled back and the runtime image was verified.
```

The external baseline hash matched again.  The temporary UI-dump file used to
confirm rollback was deleted after reading it.

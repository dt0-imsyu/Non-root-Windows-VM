# SMSS BootExecute runtime — 2026-09-05

## Scope

This test observes an earlier Windows-side boundary than `startnet.cmd`:
Session Manager BootExecute.  It did not alter firmware, EDK2, BCD,
test-signing, ACPI, GOP, PCI, graphics/vsock, PnP packages, or `startnet.cmd`.

## Native probe and SYSTEM integration

`WinAvfSmssProbe.exe` is a 3,072-byte CRT-free ARM64 PE with subsystem
`Native`.  It imports only:

```text
ntdll.dll!NtShutdownSystem
```

Its sole action is `NtShutdownSystem(ShutdownReboot)`.  Probe SHA-256:

```text
4FDC66A77A1C3C53ED21740103CED8354F1D9C6FB3854D529B22B4710C1049F1
```

The offline hive editor uses `offreg.dll` directly and never mounts the hive
in the host registry.  `Select\Current` resolves to `ControlSet001`.  That
control set had no pre-existing `BootExecute` value, so no standard command
was replaced.  The created value is:

```text
HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\BootExecute
REG_MULTI_SZ: WinAvfSmssProbe.exe
```

The probe was added at `\Windows\System32\WinAvfSmssProbe.exe`.  The target
WIM was independently extracted after update: probe and SYSTEM hashes
matched their expected inputs, and `\Windows\System32\ntdll.dll` was present.

## WIM and patch audit

```text
WIM:   625622678 bytes
       0BD3041AD4F5C3BDE4B7CD0B506EB8B4614EAE4F3BF3DCDA14BF617EA72B9883
Patch: 4477284 bytes, 10 ranges
       60F161A29B13496E993DD5DA941B79C54AAC98C82B6642680DDBD87BAE80E39A
```

`wimlib verify = PASS`.  The overlay audit against immutable baseline
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`
passed:

```text
OldTail=82936
FirstNewCluster=882627
OldClusters=76099
NewClusters=76370
ForwardWimSha256=0BD3041AD4F5C3BDE4B7CD0B506EB8B4614EAE4F3BF3DCDA14BF617EA72B9883
RollbackWimSha256=A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4
FAT1/FAT2=PASS
DirectoryInvariant=PASS
RollbackSimulation=PASS
```

## One runtime result

The device baseline hash matched before staging and the staged patch hash
matched locally.  One VM was launched.

No reboot/reset occurred.  crosvm remained alive; serial reached the existing
`ER` boundary and stopped.  Saved log:

```text
build-logs/graphics-poc-20260905/smss-bootexecute-runtime-serial.log
10367 bytes
84151440EBADAB402D02B705B78916C2FD76B3B5305DBD329FEA807D12958EC8
```

Therefore:

```text
SMSS_BOOTEXECUTE = NOT_CONFIRMED
```

The static BootExecute integration is correct, but this result does not prove
SMSS itself is defective: the Native executable may be unaccepted, or Windows
may stop before Session Manager.  No conclusion about `wpeinit`, startnet,
PnP, viogpu, or viosock follows.

## Rollback

The patch was rolled back immediately.  The app displayed:

```text
Small image patch rolled back and the runtime image was verified.
```

The external baseline SHA-256 matched afterward.  The temporary UI dump used
to read the completion status was deleted.

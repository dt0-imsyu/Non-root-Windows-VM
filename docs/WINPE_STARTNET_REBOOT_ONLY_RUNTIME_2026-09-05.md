# WinPE `startnet.cmd → wpeutil reboot` runtime — 2026-09-05

## Scope

This is the smallest follow-up to the inconclusive pre-`wpeinit` persistent
marker test.  The goal was to obtain an observable reset without relying on a
mounted writable FAT32 volume.

The source was the exact baseline WIM.  In index 2, only
`\Windows\System32\startnet.cmd` changed, to this exact 16-byte file:

```bat
wpeutil reboot
```

There was no `wpeinit`, marker, reporter, PnP code, graphics/vsock driver
change, BCD/test-signing change, or firmware change.

## Offline media and patch

WIM:

```text
624978518 bytes
48C6CD2C5E8845DE028846D9EB882C7E142D92D1948B9A0334F96477A3102D13
wimlib verify = PASS
```

Transactional patch:

```text
3187640 bytes, 9 ranges
658291E9538718346F3E94443CA13C14187BF35047B200E6FAFF7403958823DC
```

Read-only overlay audit against immutable baseline
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`:

```text
OldTail=82936
FirstNewCluster=2679
OldClusters=76099
NewClusters=76292
ForwardWimSha256=48C6CD2C5E8845DE028846D9EB882C7E142D92D1948B9A0334F96477A3102D13
RollbackWimSha256=A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4
FAT1/FAT2=PASS
DirectoryInvariant=PASS
RollbackSimulation=PASS
```

## One runtime result

The device baseline hash matched before staging and staged patch SHA matched
the local file.  Exactly one VM run was launched.

No reset/reboot occurred.  The crosvm process remained alive and serial again
stopped at the existing raw `ER` boundary.  The saved serial log is
`build-logs/graphics-poc-20260905/startnet-reboot-only-runtime-serial.log`,
10,369 bytes, SHA-256
`10D134C9DB9353BE3DEE5EB90A88E66CAA12E9FA62145B41D93AADF77F8EBAE7`.

Therefore:

```text
STARTNET_CMD_EXECUTION = NOT_CONFIRMED
WINPE_USERLAND = NOT_CONFIRMED
```

This means the reset was not observed; it does not prove the command
interpreter is absent.  In particular, it does not justify conclusions about
`wpeinit`, PnP, viogpu, or viosock.

## Rollback

Rollback was invoked immediately.  The app reported:

```text
Small image patch rolled back and the runtime image was verified.
```

The external baseline SHA-256 matched afterward.  The temporary UI dump used
to read that result was deleted.

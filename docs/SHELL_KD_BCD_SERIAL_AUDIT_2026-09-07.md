# BCD / serial KD configuration audit — 2026-09-07

## Scope

Read-only audit after the framed COM1 KD run.  No VM was launched and no BCD,
Windows image, firmware, APK, or Android state was changed.

## Verified configuration

The exact injected BCD (`DE6698BF...DFB9A11`) has:

```text
{default}.bootdebug = Yes
{default}.debug     = Yes
{dbgsettings}.debugtype = Serial
{dbgsettings}.debugport = 1
{dbgsettings}.baudrate  = 115200
```

These settings match Microsoft's documented serial KD setup: `/debug on` plus
`/dbgsettings serial debugport:1 baudrate:115200`.  The host used the matching
named-pipe serial endpoint and 115200 baud.  The framed loopback and the last
run prove this endpoint reaches crosvm `ttyS0`; U-Boot and EDK2 both report
the same legacy 16550 address (`0x3f8`).

## Concrete discrepancy

`{bootmgr}` contains no `bootdebug = Yes` element.

Microsoft documents three distinct debug stages: enabling `bootdebug` on
`{bootmgr}` for Windows Boot Manager, enabling it on the OS boot entry for
winload, and enabling `/debug` for the kernel.  The existing candidate enabled
only the latter two.  Therefore the completed negative run did **not** test
the earliest available Microsoft-signed boot-manager KD handshake.

This does not prove that the missing `{bootmgr}` setting explains the lack of
a later kernel KD packet.  It is, however, the one exact, low-risk BCD
configuration omission that can be tested before making any platform claim.

```text
KERNEL_KD_BCD_CONFIGURATION  = PASS
BOOTMGR_BOOTDEBUG             = NOT_ENABLED
COM1_MAPPING                  = PASS (ttyS0 / 0x3f8, transport proven)
WINDOWS_KD_HANDSHAKE          = NOT_OBSERVED (prior run)
```

## One proposed A/B, not performed

Create a new disposable BCD candidate from the original baseline BCD and set
only:

```text
bcdedit /store <copy> /bootdebug {bootmgr} on
bcdedit /store <copy> /bootdebug {default} on
bcdedit /store <copy> /debug {default} on
bcdedit /store <copy> /dbgsettings serial debugport:1 baudrate:115200
```

Inject it only into a newly materialized disposable clone, repeat the already
proven framed bridge once, and stop at the first KD event.  No test-signing,
signed binary, firmware, WIM, or product-media change is needed.  This A/B is
separately authorized work; it was not run in this audit.

## Sources

Microsoft's [BCDEdit `/dbgsettings` documentation](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--dbgsettings)
specifies serial `debugport:1` and 115200.  Its
[BCDEdit `/bootdebug` documentation](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--bootdebug)
explicitly distinguishes `{bootmgr}` boot debugging from the OS-loader and
kernel settings.


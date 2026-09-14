# BOOT_START load-boundary acceptance preflight — 2026-09-05

## Scope

This is a static acceptance decision.  No new WIM, transactional patch, or
tablet runtime run was created.  Firmware, BCD, test-signing, graphics,
PnP, startnet, and wpeinit were not touched.

The intended distinction was:

```text
kernel reaches boot-start loading
vs.
kernel stops before boot-start loading
```

That distinction is valid only after Code Integrity acceptance is independently
shown.  A missing DriverEntry marker otherwise has no kernel-side meaning.

## Existing custom probe

The available probe is:

```text
windows-bootstart-probe/out/WinAvfBootProbe.sys
SHA-256: 7F8E75C440048B60F0E10AFD0BF6DC0330616682A2D252C84FE3387BDE0D5B1B
PE: ARM64, Native
Imports: ntoskrnl.exe!MmMapIoSpaceEx, MmUnmapIoSpace
```

Its planned offline service is exactly:

```text
Name:      WinAvfBootProbe
Type:      1 (kernel driver)
Start:     0 (BOOT_START)
ImagePath: %SystemRoot%\System32\drivers\WinAvfBootProbe.sys
```

`DriverEntry` is deliberately bounded: it maps the FDT-established crosvm
16550 location at physical `0x3f8`, attempts `D` then `S` on the existing
serial path, and returns success.  It has no PnP, graphics, filesystem, or
user-mode dependency.

## Code Integrity result

The driver has only a local self-signed Authenticode signature:

```text
Subject: CN=WinAVF Boot-Start Diagnostic
Thumbprint: EB3A2DDA73C5B123DBA71D48E4BC9902BDBD52EC
```

`signtool verify /kp /v` fails with an untrusted-root certificate-chain error.
The INF declares `WinAvfBootProbe.cat`, but the output directory contains no
catalog.  There is no WHCP/Microsoft catalog and no documented trust path in
the current secure-boot/no-testsigning WinPE.

Therefore:

```text
BOOT_DRIVER_ACCEPTED = UNKNOWN
BOOT_START_PROBE = INCONCLUSIVE_DUE_TO_CI
```

Injecting or running this driver would make an absent `D/S` marker ambiguous,
which violates the experiment's criterion.  No runtime test was performed.

## Production-signed alternative

The WIM contains original Microsoft ARM64 boot-capable drivers, including
`acpi.sys`, `pci.sys`, `disk.sys`, and `Classpnp.sys`.  They can be trusted as
existing components, but their release binaries expose no independent serial
marker or other post-EBS observable effect.  Changing one would invalidate its
catalog-member hash.  No Microsoft/WHCP-signed ARM64 boot-start component with
an already observable marker is available locally.

## Decision and next single experiment

```text
BOOT_START_LOAD = INCONCLUSIVE
DRIVER_ENTRY = NOT_TESTED
```

Do not change BCD/testsigning or interpret missing `D/S`.  The next most
informative experiment is a **static feasibility audit of an earlier
loader/kernel-side observable boundary** that does not require custom kernel
code—before any loader/kernel patch is proposed or applied.  It must identify
one existing, documented observable channel and an acceptance path; otherwise
the project remains at the confirmed `ER` boundary.

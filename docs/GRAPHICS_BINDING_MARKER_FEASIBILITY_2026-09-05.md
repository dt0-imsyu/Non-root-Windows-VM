# Graphics binding-marker feasibility — 2026-09-05

## Scope and preserved candidate

This is a read-only feasibility audit for an observable post-EBS PnP marker.
No WIM, patch, firmware, BCD, tablet image, or device state was changed.

The following prepared candidate remains unchanged and is **not staged**:

* WIM: `627,999,710` bytes,
  `7E423FD9E6885C12E0D7C5FC70E7D0B1FEF32C4D275EE79E32CFCDA7985141E7`.
* Transaction patch: `9,236,156` bytes, `12` ranges,
  `C501636B11888FD2BB9397EFAB06D3B5523843A2131EC5ABF787D51581420AD8`.
* FAT audit: both copies match; `562` clusters are appended through
  `82936 -> 882627`; reconstructed WIM and rollback simulation both pass.

## Exact PnP state paths in upstream source

`viogpudo` has the requested semantic states:

| State | Exact callback |
| --- | --- |
| driver loaded | `DriverEntry` |
| display device bound | `VioGpuDodAddDevice` |
| display device started | `VioGpuDodStartDevice` → `VioGpuDod::StartDevice` |

`viosock` has equivalent KMDF states:

| State | Exact callback |
| --- | --- |
| driver loaded | `DriverEntry` → `WdfDriverCreate` |
| device bound | `VIOSockEvtDeviceAdd` |
| device started | `VIOSockEvtDevicePrepareHardware`, then `VIOSockEvtDeviceD0Entry` |

Thus a marker at those points would be semantically valid.  In particular,
`DriverEntry` alone is not treated as device binding.

## Why no UART marker can be inserted safely

The shipped ARM64 binaries are production-catalog signed.  Kernel-policy
verification succeeded with zero warnings for the exact original files:

* `viogpudo.sys` is a member of `viogpudo.cat`.
* `viosock.sys` is a member of `viosock.cat`.
* Both catalogs chain to `Microsoft Windows Hardware Compatibility Publisher`
  and were timestamped on 2025-11-11.

The production source routes these state traces to WPP/ETW:

* `viogpudo` release `trace.h` declares the WPP provider
  `{D6B96B2C-72BF-4CA5-BB89-9FCA5C82F020}`.
* `viosock` release `trace.h` declares the WPP provider
  `{C2D7F82F-CE5F-4408-8A37-8B9FE2B3D52E}`.

Neither provider is collected by the already-observable firmware UART path.
The only upstream direct-serial implementation is conditional debug code using
legacy x86 COM I/O port `0x3F8`; it is not an ARM PL011 UART implementation and
is not compiled into the signed release packages.

Changing either `.sys` to add `VG:*`/`VS:*` markers would change the
catalog-member hash.  It would therefore no longer be accepted by the verified
Microsoft catalog.  A companion kernel driver has the same independent
production-signing requirement.  The current AVF console cannot provide the
alternative KDCOM/kernel-debugger collection path.

## Result

```
SIGNED_RAW_UART_PNP_MARKER = BLOCKED
BLOCKER = production kernel-code signing + no ARM UART marker in signed drivers
```

No BCD/testsigning change was made.  The blocker is specific: it does not say
that either driver is incompatible or that PnP binding will fail.

## Smallest viable next instrumentation choice

Choose one explicitly before staging the prepared candidate:

1. A Microsoft/production-signed kernel marker component (not currently
   available); or
2. A minimal user-mode WinPE binding reporter which queries PnP state and
   exports the result through a separately observable storage or vsock channel.

The latter necessarily proves that a small part of WinPE userland ran, but it
does not require a graphics relay, framebuffer capture, custom kernel driver,
or BCD/testsigning change.

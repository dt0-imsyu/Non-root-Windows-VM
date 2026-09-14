# Graphics driver preflight — 2026-09-05

## Scope

Read-only preflight for the first Windows-side graphics PoC.  No WIM, FAT,
firmware, BCD, registry hive, or tablet runtime image was modified.

## Exact local packages

Both packages are in the existing local virtio payload (not copied into this
repository):

`C:\Users\denis\MainProjects\win11ontab\handoff-compact-2026-08-23\handoff-compact-2026-08-23\windows-headless-media\virtio-attestation-full\w11\arm64\viogpudo`

`C:\Users\denis\MainProjects\win11ontab\handoff-compact-2026-08-23\handoff-compact-2026-08-23\windows-headless-media\virtio-attestation-full\w11\arm64\viosock`

Both INFs report `DriverVer = 11/10/2025,100.102.104.29300` and have
`NTARM64.10.0...16299` sections.  The included PE payloads have machine
`0xAA64` (ARM64).

| Package | Signed kernel binary SHA-256 | Catalog SHA-256 | Offline result |
| --- | --- | --- | --- |
| `viogpudo` | `viogpudo.sys`: `A40C087DA06B4734D6A4DB269F338A78061E6B089BBD0324BEACC4044C659780` | `viogpudo.cat`: `3DA88C0CD3FFC95868517A8AA49F12CD6CE9A73D8B37ECEF4BDED507B228CBAE` | PASS |
| `viosock` | `viosock.sys`: `1F9F268DCCD844BCFC6D4C9D4921577A32B7555D11E80AC5D95A46D818612B43` | `viosock.cat`: `BC12D0A8933FFD1F74DD84CBD6673EB971A58F480C8948877C3BBA6A1C0BB49E` | PASS |

For both catalogs, `signtool verify /kp` succeeded with no warning or error.
The signer is `Microsoft Windows Hardware Compatibility Publisher`, issued by
`Microsoft Windows Third Party Component CA 2014`, with a Microsoft timestamp
on 2025-11-11.  These are production/WHCP-signed packages, not test-signed
packages.

## Device binding

### virtio GPU

The immutable VM serial logs enumerate `00:01.0 1AF4:1050`, for example
`build-logs\a3-append-only-runtime-serial.log` lines 100–109.

`viogpudo.inf` contains both the exact generic hardware ID
`PCI\VEN_1AF4&DEV_1050` and the more-specific subsystem/revision ID.  Its
kernel service is `VioGpuDod`, `SERVICE_KERNEL_DRIVER` (type 1), PnP demand
start (start 3), with `msdv.inf` included.  The platform section admits ARM64
Windows 10 build 16299 and newer, including the ARM64 WinPE/Windows generation
in this image.  Binding itself remains the next runtime assertion.

`ARM64_VIOGPU_DRIVER_COMPAT = PASS`

### virtio vsock

The same immutable VM serial logs enumerate `00:08.0 1AF4:1053`, for example
`build-logs\a3-append-only-runtime-serial.log` line 108.  This is the actual
vsock device in this crosvm VM, not an inference from the Android API.

`viosock.inf` contains the exact generic hardware ID
`PCI\VEN_1AF4&DEV_1053` (and a specific subsystem/revision ID); it also
contains the legacy `DEV_1012` match.  The kernel `viosock` service is
`SERVICE_KERNEL_DRIVER`, PnP demand start, normal error control, and uses
KMDF 1.15.  The package also contains its signed Winsock provider components
(`viosockwspsvc.exe`, `viosocklib.dll`) and installs the provider service as an
auto-start user-mode service.  Its ARM64 platform section is likewise
`NTARM64.10.0...16299`.

`ARM64_VSOCK_DRIVER_COMPAT = PASS`

## Windows frame source

The upstream display-only driver has a concrete CPU-readable frame source:

1. `VioGpuDod::PresentDisplayOnly` receives the OS source pointer and dirty
   rectangles (`pSource`, `NumDirtyRects`, `pDirtyRect`).
2. It writes to `m_CurrentMode.FrameBuffer`.
3. `CreateFrameBufferObj` creates a virtio resource backed by
   `m_FrameSegment`, stores the driver's virtual mapping in
   `pCurrentMode->FrameBuffer`, attaches it to the virtio resource, and makes
   it scanout 0.
4. The driver sends the changed rectangles through `TRANSFER_TO_HOST_2D` and
   `RESOURCE_FLUSH`.

Therefore the active BGRA backing store is CPU-readable **inside
`viogpudo`**.  It is not a public cross-driver framebuffer: upstream
`QueryInterface` returns `STATUS_NOT_SUPPORTED`; no exported capture callback,
mirror protocol, shared section, or external frame handle was found.  A second
kernel component must not dereference the driver's private virtual mapping.

The technically smallest capture point is a deliberately designed extension
inside `PresentDisplayOnly`/`ExecutePresentDisplayOnly`: copy the already
available dirty rectangles into a separately owned BGRA staging allocation,
then signal a producer at a safe execution level.  It must not retain
`pSource` past the present call.  A separate custom build of `viogpudo` would
lose the observed Microsoft production signature and therefore is not
loadable under the current secure-boot/no-testsigning policy unless it is
independently production-signed.  No such capture component is being built in
this PoC.

`WINDOWS_FRAME_SOURCE = IDENTIFIED`

## Next reversible test

Use elevated Microsoft DISM to inject the two already-verified packages into a
throwaway copy of the known-good `boot.wim` index 2, then create a new
transactional patch from the immutable raw baseline.  The first runtime test
only asserts PnP binding of `viogpudo` and `viosock`; it does not attempt frame
capture, a relay, or a vsock hello.

## Prepared candidate — not staged to the tablet

DISM successfully injected both packages into index 2 of a throwaway WIM copy:

| Item | Value |
| --- | --- |
| WIM size | `627,999,710` bytes |
| WIM SHA-256 | `7E423FD9E6885C12E0D7C5FC70E7D0B1FEF32C4D275EE79E32CFCDA7985141E7` |
| Transaction patch | `build-logs\\graphics-poc-20260905\\viogpu-viosock-fat-grow.patch` |
| Patch SHA-256 | `C501636B11888FD2BB9397EFAB06D3B5523843A2131EC5ABF787D51581420AD8` |
| Patch size/ranges | `9,236,156` bytes / `12` ranges |
| New clusters | `562`, bridged from `82936` to `882627` |

The independent serialized-patch audit passed: baseline SHA-256 matched
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`, both
FAT copies agreed, the reconstructed WIM SHA-256 matched the WIM above, and
the rollback reconstruction matched the original WIM SHA-256
`A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4`.

This candidate is deliberately **not staged or applied**.  The current
Windows serial channel proves EBS but cannot observe Windows PnP state, and
WinPE userland is not yet confirmed.  Running it now would yield only another
EBS result, not either required `WINPE_VIOGPU_BOUND` or
`WINPE_VSOCK_BOUND` result.  A separately authorized, minimal Windows-side
binding marker is required before this candidate may be used for the one
runtime binding test.

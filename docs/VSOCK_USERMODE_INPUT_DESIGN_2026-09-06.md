# WinAVF post-EBS vsock input — static design and agent build

## Decision

The blocked Samsung AVF virtio-keyboard API is not a blocker for post-EBS
Windows input. The product transport is:

```text
Android touch / mouse / keyboard
  → WinAVF APK
  → VirtualMachine.connectVsock(4050)
  → production-signed ARM64 viosock
  → WinAvfInput.exe
  → SendInput (first user-mode proof)
```

This does **not** solve UEFI input. Pre-EBS input remains a separate optional
firmware-relay problem. It also does not make `SendInput` a final replacement
for a properly signed virtual HID driver on secure desktop, logon, or other
non-interactive surfaces.

## Exact host and guest contracts

The locally audited AVF API exposes `VirtualMachine.connectVsock(long port)`;
the platform source describes it as a raw app-to-VM connection and restricts
guest-bindable ports to `1024..0xffffffff`. The guest therefore listens on
port `4050`, then the app connects after the agent exists.

The already staged-for-later Windows package is the production-signed ARM64
`viosock` package. Its INF contains the exact compatible IDs
`PCI\\VEN_1AF4&DEV_1012` and `PCI\\VEN_1AF4&DEV_1053`, installs the kernel
driver and the Winsock provider service, and has no source modification.
`signtool verify /kp` passes for `viosock.sys` (SHA-256
`1F9F268DCCD844BCFC6D4C9D4921577A32B7555D11E80AC5D95A46D818612B43`);
the matching catalog SHA-256 is
`BC12D0A8933FFD1F74DD84CBD6673EB971A58F480C8948877C3BBA6A1C0BB49E`.

The agent gets its runtime address family by asking `\\??\\Viosock` through
`IOCTL_GET_AF`, then uses Winsock `socket/bind/listen/accept` with the viosock
`SOCKADDR_VM` ABI. It does not hard-code an address-family number.

## Built artifact

`winavf-vsock-agent/out/WinAvfInput.exe` is a 4,096-byte ARM64 Windows GUI PE:

```text
SHA-256: CFFDAA8FBDA4BF1B692D9D23A0F3EC28618116E2A95EF2989FECD3617B9FE80F
imports: KERNEL32.dll; WS2_32.dll
```

It has no C runtime or static `USER32.dll` dependency. On client connect it
sends binary `WVH1`; only on a `WVI1` keyboard command does it dynamically load
`user32.dll` and call `SendInput`. Exact wire format and build command are in
`winavf-vsock-agent/README.md`.

## Runtime gates — do not collapse them

```text
WINPE_USERLAND             = NOT_CONFIRMED
WINPE_VSOCK_BOUND          = NOT_TESTED
VSOCK_HELLO                = NOT_TESTED
WINDOWS_INPUT_VSOCK        = NOT_TESTED
WINPE_SETUP_VISIBLE        = NOT_CONFIRMED
```

At the initial agent-preparation point no WIM candidate was built. The previous
`startnet.cmd = wpeutil reboot` and pre-wpeinit tests showed no external effect,
so adding viosock, the agent, and a graphics relay in one run would not
localize a failure.

## Offline HELLO WIM candidate — not staged

An append-only candidate was built from the preserved signed-driver WIM,
`boot-wim-viogpu-viosock.wim` (SHA-256
`7E423FD9E6885C12E0D7C5FC70E7D0B1FEF32C4D275EE79E32CFCDA7985141E7`).
It changes only these index-2 paths:

```text
\WinAvf\WinAvfInput.exe
\Windows\System32\startnet.cmd
```

`startnet.cmd` starts the agent in the background, then runs `wpeinit`; the
agent waits up to 60 seconds for the viosock PnP device to appear. The
candidate WIM is
`build-logs/gop-poc-20260906/boot-wim-viogpu-viosock-hello-r1.wim`, 629,583,762
bytes, SHA-256 `505A774DC101D18A6BE02B63CAE2E6C2037C40662A339D049BD022EDA4D6E9C4`.
`wimlib verify` passes; extracted agent SHA-256 is
`A0F03AC67C925319FBC1FC593CB4F2ADE67D23B72E2B585D39D118AD29F72F99`, and
the extracted viosock driver retains the verified signed hash.

It is intentionally **not staged**. The available local raw image is the old
`winavf-a3-append-only-runtime.img`, not a proven copy of the immutable
baseline SHA-256 `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.
Generating a range patch from it could not satisfy the transactional baseline
precondition. Obtain a read-only local copy of that exact baseline, or an
already verified matching raw source, before calling the FAT-grow patch builder.

## Single next runtime A/B

After an independent `WINPE_USERLAND = PASS` boundary exists, make one
transactional WinPE candidate containing only the unchanged signed viosock
package plus `WinAvfInput.exe` launched after that proven boundary. The APK
attempts `connectVsock(4050)` and checks for 16-byte `WVH1`.

`WVH1` establishes `VSOCK_HELLO = PASS`. Only in a separately visible
WinPE/Setup desktop should one `A` key down/up packet be sent; a visible `A`
is then the proof for `WINDOWS_INPUT_VSOCK = PASS`.

## Sources

- Local AVF framework source: `framework-virtualization-source` API and
  `VirtualMachine.java` (`connectVsock`).
- Local ARM64 package:
  `windows-headless-media/virtio-attestation-full/w11/arm64/viosock`.
- Upstream ABI reference:
  https://github.com/virtio-win/kvm-guest-drivers-windows/blob/master/viosock/inc/vio_sockets.h

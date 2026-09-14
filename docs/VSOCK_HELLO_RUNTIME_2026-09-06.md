# WinPE viosock HELLO runtime — 2026-09-06

## Scope

One transactional runtime test of the post-EBS vsock boundary. Firmware, BCD,
the production-signed viosock package, and external baseline media were not
modified. The app applied the patch only to its private runtime copy, then
rolled it back immediately after the one run.

## Offline candidate

```text
WIM:       boot-wim-viogpu-viosock-hello-r1.wim
WIM SHA:   505A774DC101D18A6BE02B63CAE2E6C2037C40662A339D049BD022EDA4D6E9C4
Patch:     vsock-hello-r1-fat-grow.patch
Patch SHA: 93DC7C2A129135B2618E7B1895CB8A75603A2EB19019350CCFF76DA025A54595
Patch:     12,407,424 bytes, 13 ranges
```

The patch audit passed against baseline
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`:

```text
OldTail=82936
FirstNewCluster=882627
OldClusters=76099
NewClusters=76854
FAT1/FAT2=PASS
DirectoryInvariant=PASS
ForwardWimSha256=505A774DC101D18A6BE02B63CAE2E6C2037C40662A339D049BD022EDA4D6E9C4
RollbackSimulation=PASS
```

Index 2 starts `WinAvfInput.exe` in the background, then calls `wpeinit`.
The agent waits for the signed viosock PnP device, listens on port 4050, and
would emit raw `WVH1`. The APK retries only `connectVsock(4050)` for 60
seconds; it sends no input packet.

## One runtime result

The tablet baseline hash matched before staging and the staged patch hash
matched the local patch. The only guest-facing result was:

```text
transport=AVF_CONNECT_VSOCK
port=4050
result=VSOCK_HELLO_NOT_OBSERVED
lastError=ServiceSpecificException: Failed to connect

Caused by:
    No such device (os error 19)
```

The serial capture again reaches the established `ER` boundary and stops.
No second run was made.

The app then reported: `Small image patch rolled back and the runtime image
was verified.` The external baseline SHA-256 after rollback again matches
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

Artifacts:

- `build-logs/gop-poc-20260906/vsock-hello-r1-runtime-report.txt`, SHA-256
  `91B317668E3A2D760DA18B3A9656FEB04CE012EB452C7DB4CB2B0033586505B1`.
- `build-logs/gop-poc-20260906/vsock-hello-r1-runtime-serial.log`, SHA-256
  `BCD8318269495EDA1D29313B2252DD2F0758B6E6F8C3BDE8C2DDA24225B661D6`.

## Classification

```text
VSOCK_HELLO          = NOT_OBSERVED
WINPE_VSOCK_BOUND    = NOT_CONFIRMED
WINDOWS_INPUT_VSOCK  = NOT_TESTED
WINPE_USERLAND       = NOT_CONFIRMED
```

`No such device` is not a viosock rejection result: the existing earlier
WinPE/startnet boundary remains unobserved, so the agent may never have run
or PnP may never have bound the device. Do not retry alternative viosock,
graphics, or input variants until a new independent early-Windows observation
method exists.

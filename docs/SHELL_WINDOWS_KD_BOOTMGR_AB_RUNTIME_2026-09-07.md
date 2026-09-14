# Boot Manager bootdebug KD A/B — 2026-09-07

## Scope

Exactly one shell-owned disposable Windows VM was run.  Relative to the prior
framed KD run, the only intended media change was:

```text
{bootmgr}.bootdebug = Yes
```

The candidate BCD SHA-256 was
`9C4A3EF1BB2D15D29F39358573E70E9407ADEE9894A929642D1B66465D255D27`.
The new raw clone SHA-256 was
`652EEC534B9511B8F1211DDBE6FE553A8707A7E67AFBF7351AB5D46E24FA38E7`.
`BOOTAA64.EFI` re-extracted identically before and after injection.

## Runtime

The staged clone SHA matched exactly before launch.  KD pipe and framed COM1
bridge connected; CID `2109` ran with the established one-vCPU / 4-GiB shell
topology.  The bridge received 10,109 bytes of guest serial output and sent
513 KD synchronization bytes to guest COM1.  crosvm reported no wait-context
EPERM.

The key A/B observation is deterministic:

| Candidate | Last Windows-side visible boundary |
|---|---|
| Previous (`{bootmgr}.bootdebug` absent) | Boot Manager UI then `Loading files...` |
| This A/B (`{bootmgr}.bootdebug = Yes`) | `IMAGE_AUDIT start enter` for `BOOTAA64.EFI`; no `Loading files...` |

KD itself remained at `Waiting to reconnect`; no target KD packet was decoded.
The A/B therefore proves that Boot Manager consumes and acts on the newly
enabled bootdebug setting, but it does not prove a completed KD protocol
handshake.

```text
BOOTMGR_BOOTDEBUG_EFFECT = PASS
SHELL_KD_COM1_RX         = PASS
WINDOWS_KD_HANDSHAKE     = NOT_OBSERVED
```

## Cleanup

The exact Android temporary staging directory was removed immediately after
evidence collection.  No test VM remains.  The immutable product baseline was
then independently rehashed as
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.

## Next step

Do not repeat this same BCD A/B.  The remaining question is why Boot Manager
does not emit a KD response over an otherwise proven COM1 bridge.  The next
work should be a read-only ARM64 Boot Manager / SPCR / serial-debug transport
audit, not another runtime or platform change.


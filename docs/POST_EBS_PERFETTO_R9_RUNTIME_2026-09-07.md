# Bounded post-EBS Perfetto runtime — r9 — 2026-09-07

## Scope

Exactly one WinAVF VM launch was made.  The run used the existing r9 firmware
bundle unchanged; no Windows media, WIM, BCD, Android APK, EDK2 source, or
driver was changed.  The only runtime mutation was the existing reversible
one-range r9 firmware patch, which was rolled back immediately after capture.

## Preflight

| item | result |
|---|---|
| immutable external runtime image SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` — PASS |
| r9 FD SHA-256 | `EB023DF0CA527F6E428D5B0CCE87CC67895B4C69443B64661CE7FAD4BD65C346` — PASS |
| r9 patch SHA-256 | `54CC7498867ADFD29AE82320FCEC17FE338B29E69D6E3D9B389E1981DD2AD124` — PASS |
| r9 patch range | raw offset `7250927616`, length `2097152` |
| VM launch count | 1 |

The launcher verifies the complete baseline SHA before its forward write.  It
also verifies the old/new range hashes and keeps the rollback bytes.

## Capture

Perfetto began before the start intent and captured for 90 seconds with a 48
MiB buffer.  The intentionally narrow ftrace set was:

```text
sched/sched_switch
sched/sched_wakeup
sched/sched_waking
block/block_rq_issue
block/block_rq_complete
irq/irq_handler_entry
irq/irq_handler_exit
```

`adb exec-out` preserved the original transport capture at
`build-logs/20260907-perfetto-r9-post-ebs/runtime-r9-post-ebs.raw.pftrace`
(31,758,239 bytes, SHA-256
`F74628EE0B37DABEC4DFB843FC7C60D0FCFF4C680AC7858DE0A498E8B53757C8`).
Android's `perfetto` command interleaved a 103-byte textual prologue and a
78-byte textual completion line around the protobuf stream.  The untouched
transport capture is retained; `runtime-r9-post-ebs.decoded.pftrace` removes
only those wrappers for local Trace Processor analysis (31,758,058 bytes,
SHA-256 `ED8B3E2451653353A4C967216649BCF28B7CAF7EDC085E980B955BBD9EC97315`).

The raw serial capture is
`runtime-r9-raw-serial.log` (1,290,719 bytes, SHA-256
`38600F70A9333A5529B3398F25524DB3D972D11C306C97DDCF06924404E696FE`).  It
ends with `BES` at offsets `1290716..1290718`: wrapper entry, RuntimeDxe EBS
event, then successful return from the original `ExitBootServices()`.

## Timeline and attribution

* Perfetto start: `2026-09-07T14:41:10.9890605+03:00`.
* VM start intent: `2026-09-07T14:41:13.0606007+03:00`.
* A host serial sample at `2026-09-07T14:42:07.3648952+03:00`, 56.376 seconds
  after trace start, already contained the final `BES` bytes.
* The trace spans 89.930 seconds.  Analysis deliberately uses only its
  60.000–89.930 second tail, a conservative interval wholly after the latest
  possible observed `BES` time.

The launched VM was uniquely identifiable as PID `16987`,
`crosvm_winavf-gop-ebs-r1`; its command line identifies the WinAVF disk and
its `crosvm_vcpu0` thread is TID `17000`.

In the conservative post-BES interval, TID `17000` had 7,485 scheduler slices
and 29,915.517 ms of scheduled CPU time.  It was scheduled through trace time
89.929 seconds, effectively one full host CPU for the complete 29.93-second
tail.  This is direct host evidence that the guest vCPU continued executing
well after `BES`; it does **not** identify which Windows instruction was
executing.

The VM's `virtio_blk` thread (TID `17055`) had activity only from trace time
15.446 through 26.041 seconds.  It had no observed scheduling in the
conservative post-BES window.  There were 5,992 global `block_rq_issue` and
5,993 global `block_rq_complete` events from 60.267 through 88.883 seconds,
but those events cannot be attributed to WinAVF: no post-window event belongs
to its `virtio_blk` worker.  They are retained as host context, not guest-I/O
proof.

```text
POST_EBS_VCPU_EXECUTION = PASS
POST_EBS_BLOCK_ACTIVITY = NOT_OBSERVED  (VM-attributable virtio-block activity)
POST_EBS_GLOBAL_BLOCK_ACTIVITY = PASS   (not attributable to the VM)
```

## Rollback

The existing launcher rollback was invoked immediately after capture.  Its
UI reported: `Small image patch rolled back and the runtime image was
verified.`  The external immutable image was then independently hashed again
and exactly matched:

```text
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

All raw inputs, process snapshots, SQL outputs, extraction metadata, and
`SHA256SUMS.txt` are retained in `build-logs/20260907-perfetto-r9-post-ebs/`.

## Boundary

The run removes the possibility that the VM simply stopped executing at the
serial `BES` boundary.  It does not prove Windows kernel entry, guest forward
progress, or post-EBS storage I/O.  No second run was made.

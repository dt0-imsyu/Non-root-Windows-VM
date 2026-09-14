# GenieZone ftrace post-EBS r9 runtime — 2026-09-07

## Result

```text
GENIEZONE_FTRACE_PERFETTO_FOR_WINAVF = NOT_USABLE
VMM_GUEST_EVENT_OBSERVER              = BLOCKED
WINDOWS_KERNEL_ENTRY                  = UNKNOWN
```

The device exposes the vendor `geniezone` ftrace group and Perfetto accepted
all three requested event names.  During the one bounded WinAVF VM run it
emitted **zero** `mtk_vcpu_exit`, `mtk_hypcall_enter`, or `mtk_hypcall_leave`
records, while the launch-specific `crosvm_vcpu0` consumed 85.551 seconds of
scheduled CPU time.  This is a negative result about the observer, not about
Windows kernel entry or forward progress.

## Scope and safety

This was exactly one VM launch.  It used only the pre-existing r9 FD and exact
existing one-range transactional patch; no firmware source/FD bytes, Windows
media/WIM/BCD, driver, Android APK, graphics, input, or VM configuration was
changed.  The patch was rolled back immediately after capture.

| Item | Result |
|---|---|
| Immutable baseline before patch | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` — PASS |
| r9 FD SHA-256 | `EB023DF0CA527F6E428D5B0CCE87CC67895B4C69443B64661CE7FAD4BD65C346` — PASS |
| r9 patch SHA-256 | `54CC7498867ADFD29AE82320FCEC17FE338B29E69D6E3D9B389E1981DD2AD124` — PASS |
| r9 range | offset `7250927616`, length `2097152` |
| VM launches | 1 |
| Rollback UI | `Small image patch rolled back and the runtime image was verified.` |
| crosvm after rollback | absent |
| Immutable baseline after rollback | exact same SHA-256 — PASS |

## Capability check

The unprivileged `adb shell` identity could enumerate, but not directly read
the format of, these kernel tracepoints:

```text
/sys/kernel/tracing/events/geniezone/mtk_vcpu_exit
/sys/kernel/tracing/events/geniezone/mtk_hypcall_enter
/sys/kernel/tracing/events/geniezone/mtk_hypcall_leave
```

Perfetto accepted the following bounded 95-second configuration.  This is
stronger than a name-only inventory, but still does not establish that vendor
trace data is released to an ordinary-shell session for this custom VM.

```text
sched/sched_switch
sched/sched_wakeup
sched/sched_waking
geniezone/mtk_vcpu_exit
geniezone/mtk_hypcall_enter
geniezone/mtk_hypcall_leave
```

## Retained evidence

Android's `perfetto -o -` output again has a 103-byte textual prefix and
78-byte textual suffix around the protobuf trace.  Both forms are retained;
only the decoded payload was parsed.

| File | Bytes | SHA-256 |
|---|---:|---|
| `build-logs/geniezone-post-ebs-r9-20260907/runtime-r9-geniezone-attempt2.raw.pftrace` | 12,995,536 | `B646FFC911ECCC0C31E81923B0811F4B7D827EDF5C9E4D7DAA709C1ABADEB33A` |
| `build-logs/geniezone-post-ebs-r9-20260907/runtime-r9-geniezone-attempt2.decoded.pftrace` | 12,995,355 | `205EA2276AC1EB08AF1933B0AB563CE9134976C124823DB365647E82BE3F7BB3` |
| `build-logs/geniezone-post-ebs-r9-20260907/runtime-r9-geniezone.raw-serial.log` | 1,290,721 | `6BB08CAD7C04B2B9FA251388A794C2A8EB9642980669E8779E968647086C6746` |

The raw serial contains the proven ExitBootServices-return sequence and ends
at byte offset `1290718` with `BES`; it does not supply a later Windows-side
marker.

## Trace Processor result

The decoded payload contained only scheduler ftrace records:

| ftrace name | Count |
|---|---:|
| `sched_switch` | 323,617 |
| `sched_wakeup` | 179,590 |
| `sched_waking` | 179,586 |
| all requested `mtk_*` / GenieZone records | **0** |

The actual WinAVF crosvm PID was `23378`.  Its principal vCPU thread was
`crosvm_vcpu0` TID `23404`: 24,302 scheduler slices and 85,550.753 ms CPU,
scheduled from 1,048,487.677985 through 1,048,573.301238 trace seconds.  The
same process's `virtio_blk` worker TID `23426` ran for 639.044 ms.  Therefore
absence of vendor packets is not caused by the VM failing to execute.

No exact relationship between trace start and `BES` is claimed: Perfetto and
the single launch intent were started concurrently.  The trace establishes
that vendor ftrace does not provide a usable VMM event stream during the
bounded run, not a timestamped guest-stage timeline.

## Decision

The public/vendor tracepoint names are insufficient: this device does not
release events for this GenieZone-backed custom VM to the accessible Perfetto
session.  Repeating with the same provider would have no new diagnostic value.

The only remaining direct ways to distinguish `winload` handoff, kernel entry,
timer delivery, and early kernel spin are:

1. a genuine byte-transparent bidirectional Windows KD transport; or
2. a privileged vendor VMM/GZVM interface that exposes this VM's guest state.

Neither is available under the current no-root/no-system-modification model.

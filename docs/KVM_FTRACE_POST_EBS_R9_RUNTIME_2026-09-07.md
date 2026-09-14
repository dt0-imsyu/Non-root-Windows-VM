# KVM ftrace post-EBS r9 runtime — 2026-09-07

## Result

```text
KVM_FTRACE_PERFETTO_FOR_WINAVF = NOT_USABLE
VMM_GUEST_EVENT_OBSERVER        = BLOCKED
WINDOWS_KERNEL_ENTRY            = UNKNOWN
```

The VM executed extensively, but Perfetto emitted no KVM, vGIC, GZVM, or
GenieZone ftrace packets. This is not evidence that the VM stopped or that
Windows did not enter its kernel; it proves that these tracepoints do not give
an observable guest-event stream for this unprivileged WinAVF run.

## Scope

One VM launch only used the pre-existing r9 firmware bundle. No firmware source
or FD bytes, Windows media/WIM/BCD, Android APK, driver, or VM configuration
was changed. The only temporary runtime mutation was the existing, verified,
one-range r9 firmware patch. It was rolled back immediately after capture.

An earlier host-only Perfetto start attempt was terminated before any VM start
because its launcher process setup failed. Its retained trace is explicitly
not runtime evidence. The run described below is the sole VM launch.

## Preflight and rollback

| Item | Result |
|---|---|
| External immutable baseline before forward patch | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` — PASS |
| r9 FD SHA-256 | `EB023DF0CA527F6E428D5B0CCE87CC67895B4C69443B64661CE7FAD4BD65C346` — PASS |
| r9 patch SHA-256 | `54CC7498867ADFD29AE82320FCEC17FE338B29E69D6E3D9B389E1981DD2AD124` — PASS |
| r9 range | offset `7250927616`, length `2097152` |
| VM launches in this experiment | 1 |
| Rollback UI | `Small image patch rolled back and the runtime image was verified.` |
| External immutable baseline after rollback | exact same SHA-256 — PASS |

The r9 staging bundle was absent after the run, the WinAVF crosvm process was
absent after the rollback intent, and the external image hash was re-read from
the tablet.

## Capture

Perfetto and the one VM start were initiated together and the capture ran for
95 seconds. The launch log records that the attempted three-second shell delay
was not accepted (`sleep: Needs 1 argument`); this report therefore makes no
claim that the trace starts before VM launch or at a known offset from `BES`.
The bounded ftrace configuration was:

```text
sched/sched_switch
sched/sched_wakeup
sched/sched_waking
kvm/kvm_entry
kvm/kvm_exit
kvm/kvm_wfx_arm64
kvm/kvm_timer_update_irq
kvm/vgic_update_irq_pending
```

The original Android transport capture contains a 103-byte textual prologue and
a 78-byte textual trailer around the protobuf payload, as did the prior r9
Perfetto capture. Both raw and decoded forms are retained:

| File | Bytes | SHA-256 |
|---|---:|---|
| `build-logs/kvm-post-ebs-r9-20260907/runtime-r9-kvm-post-ebs-attempt2.raw.pftrace` | 15,478,139 | `8A8BBE8BFAA98BE6298E2421D0FBDE17544B5F5206D1C8B80C8A5244F5BFBC35` |
| `build-logs/kvm-post-ebs-r9-20260907/runtime-r9-kvm-post-ebs-attempt2.decoded.pftrace` | 15,477,958 | `A4D93A196E625B4242204AF3FDEE3B18433AB5465862A5BC20B84580372C70E2` |
| `build-logs/kvm-post-ebs-r9-20260907/runtime-r9-kvm-post-ebs.raw-serial.log` | 1,290,719 | `38600F70A9333A5529B3398F25524DB3D972D11C306C97DDCF06924404E696FE` |

The raw serial is byte-identical to the prior r9 evidence and ends in `BES`:
the wrapper entry, RuntimeDxe ExitBootServices event, and successful return
from the original `ExitBootServices()`.

## Trace Processor result

The decoded trace has exactly 813,164 `ftrace_event` records:

| ftrace name | Count |
|---|---:|
| `sched_switch` | 383,547 |
| `sched_wakeup` | 214,810 |
| `sched_waking` | 214,807 |
| all requested `kvm_*` / `vgic_*` / GZVM / GenieZone names | **0** |

The WinAVF process was PID `21711`. Its `crosvm_vcpu0` thread (TID
`21737`) had 23,635 scheduler slices, 85,312.269 ms scheduled CPU time, and
was scheduled through 85.585 seconds of the 95-second trace. Thus the missing
KVM packets cannot be explained by a non-running vCPU. `virtio_blk` TID
`21933` ran for 621.441 ms and last appeared at 11.739 seconds, but KVM event
absence prevents attribution of guest exits, timer delivery, or injection.

## Decision

The device exposes KVM event names and Perfetto accepts them in a configuration,
but that does not imply packets for the GenieZone-backed custom VM. The trace
cannot distinguish producer-policy suppression from absence of generic KVM hooks
in this backend. Practically, neither gives guest PC, exception, entry/exit,
timer, or vGIC observation.

No further KVM/ACPI/timer firmware A/B is justified. The remaining direct
observability requirement is a genuine bidirectional Windows KD transport or a
privileged vendor VMM/GZVM trace interface that exposes this VM's guest state.

# Post-EBS observability forensic audit

Date: 2026-09-07  
Device: Samsung SM-X736B (`gts11`), Android 16 / API 36, One UI release build,
GenieZone, locked / green verified boot.  
Scope: read-only inspection only. No WinAVF VM was started; no firmware, WIM,
BCD, driver, APK, image, SELinux, system or vendor component was changed.

## Fixed Windows boundary

```text
winload.efi invoked                     = PASS
original ExitBootServices() returned OK = PASS (raw BES)
SetVirtualAddressMap                    = NOT_OBSERVED
Windows kernel entry                    = UNKNOWN
direct kernel-entry observer            = BLOCKED
```

The r9 negative observation remains valid and is not reinterpreted here.

## Executive result

```text
PUBLIC_AVF_DEBUG_IO                    = PARTIAL
CROSVM_BIDIRECTIONAL_SERIAL_CAPABILITY = YES
AVF_EXPOSES_SERIAL_RX                  = NO
HIDDEN_BIDIRECTIONAL_SERIAL_FD          = EXISTS_BUT_PRIVILEGED
KD_OVER_CURRENT_CROSVM_UART            = CONDITIONAL
HOST_LOGCAT_POST_EBS_SIGNAL             = LIMITED
AVF_DUMPSYS_OBSERVABILITY               = COARSE_ONLY
ADB_SHELL_HOST_OBSERVABILITY            = PARTIAL
PERFETTO_AVF_TRACE                      = PARTIAL
CROSVM_RUNTIME_STATS                    = PRIVILEGED
GZVM_HOST_TRACE                         = PRIVILEGED
SAMSUNG_GUEST_INPUT_DEBUG_PATH          = PRIVILEGED
VIRTIO_DEVICE_IO_TRACE                  = PARTIAL
POST_EBS_OBSERVABILITY_PATH             = AVAILABLE_WITH_SAFE_ONE_RUN_CONFIG
```

`AVAILABLE_WITH_SAFE_ONE_RUN_CONFIG` means a future **host-only** `adb shell`
Perfetto trace can establish crosvm process survival, scheduling of its vCPU
and device-worker threads, and temporally-correlated host block/IRQ activity.
It does **not** prove execution of a particular Windows instruction, kernel
entry, virtio request completion, or a GZVM exit reason.

## Candidate comparison

| Candidate | Earliest boot stage | Guest modification | Host modification | Root | Bidirectional | Untrusted app | adb shell | Proves kernel alive | Proves device I/O | Supports KD | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Captured console output | pre-EBS through `BES` | none | none | no | no | yes | yes | no after the last guest byte | no | no | Existing PASS, output-only. |
| Hidden AVF console RX | any stage, COM1/`ttyS0` | none | none | no | yes | no | no direct FD | conditional if exposed | no | yes | Exists internally, but inaccessible. |
| crosvm control socket / balloon stats | VM running | none | none | no | control protocol | no | no | no | balloon only | no | Service-owned, not a diagnostic API. |
| logcat crosvm/service records | crosvm start through exit | none | none | no | no | no | yes | only process/error evidence | no | no | Useful supporting evidence only. |
| `/proc` and `ps -T` sampling | crosvm start through exit | none | none | no | no | no | yes | process/thread survival only | no | no | Safe but coarse. |
| Perfetto `sched` + `disk` + `irq` | crosvm process lifetime | none | transient trace capture only | no | no | no | yes | process/vCPU-worker scheduling only | host I/O correlation only | no | **Best candidate**. |
| KVM / GenieZone ftrace events | vCPU enter/exit / hypercall | none | trace configuration | likely privileged on this build | no | no | not established | potentially stronger | potentially | no | Event groups exist, but direct access is denied; not a current path. |
| crosvm device/control statistics | device runtime | none | none | no | internal control socket | no | no | no | balloon only in audited source | no | Privileged only. |
| Windows serial KD / bootdebug | loader and kernel debug init | BCD only, later | requires RX bridge | no if RX exposed | yes | no | no direct bridge | yes | debugger-dependent | yes | Conditional on a public raw RX endpoint; do not change BCD now. |

## Track 1 — actual AVF API

The actual APEX contains
`/apex/com.android.virt/javalib/framework-virtualization.jar` (197,885 bytes).
Its DEX strings contain `getConsoleOutput`, `getLogOutput`, `connectVsock`, and
`getConsoleInput`. Local framework source explains the last item: it is
`@hide @TestApi public OutputStream getConsoleInput()`.

The relevant source chain is:

```text
VirtualMachine.createVmInputPipes()
  -> mConsoleInReader passed through Binder as consoleInFd
  -> crosvm RunContext.console_in
  -> --serial=...,input=/proc/self/fd/N,hardware=serial,num=1

mConsoleInWriter
  -> hidden getConsoleInput() OutputStream
```

The decisive device-specific evidence remains stronger than DEX strings: the
installed `com.example.winavf`, target SDK 36, made the exact reflection call
`VirtualMachine.getConsoleInput()` and received `NoSuchMethodException`.
Therefore bytecode presence is not caller access. The API is hidden/TestApi
and not callable by this ordinary application under the release build's
non-SDK access policy. There is no public serial write method, writable console
`ParcelFileDescriptor`, debug FD, stats, metrics or trace method.

`getConsoleOutput(): InputStream` and `getLogOutput(): InputStream` are
read-only output. `connectVsock(long): ParcelFileDescriptor` is a public,
bidirectional socket only after a guest service listens; it is not a UART and
cannot bootstrap serial KD before Windows drivers/user mode.

## Track 2 / 3 — crosvm serial and FD ownership

The audited AVF crosvm source has explicit duplex serial support. It accepts
only `hvc0` or `ttyS0` as console input devices and adds `input=<preserved-fd>`
only for the selected device. The existing WinAVF guest reports the 16550-like
UART at I/O base `0x3f8`, with 115200 baud in the loader logs. Thus the current
endpoint is a COM1-like UART, not PL011, and would be compatible in principle
with a serial debugger if the missing host-to-guest byte stream were exported.

| FD / channel | Direction | Purpose / owner | App access | adb shell access |
| --- | --- | --- | --- | --- |
| `console_out` pipe | guest TX -> app | caller-created writer passed to service/crosvm; read end becomes `getConsoleOutput()` | read | indirect only |
| `console_in` pipe | app -> guest RX | caller-created hidden writer; reader is passed to crosvm as `input=` | no public handle | no |
| log pipe | guest TX -> app | `getLogOutput()` | read | indirect only |
| vsock PFD | both directions | public connection to a listening guest port | yes, after listener | yes through app only |
| crosvm control socket | service <-> crosvm | internal `--socket /proc/self/fd/15`; balloon control in source | no | no |
| block FDs | crosvm <-> app-owned image | inherited `/proc/self/fd/*`; no per-request export | image file only | no live counters |
| Terminal input FDs | Android UI -> virtio input | Terminal crosvm uses separate touch/keyboard/mouse FDs | no | no |

Shell could read process status but was denied `/proc/<crosvm-pid>/fd`,
`fdinfo`, and `io`. It was also denied the `virtualizationservice` process FD
directory and `/data/misc/virtualizationservice`. This confirms the control and
input descriptors cannot be recovered by a normal app or `adb shell` without
crossing SELinux/process ownership boundaries.

## Track 4 / 14 — Windows KD

The preserved baseline WinPE contains Microsoft-signed ARM64 `winload.efi`,
`ntoskrnl.exe`, `kdcom.dll`, and `kdnet_uart16550.dll`; prior `/kp` verification
passed. The preserved BCD audit has `{dbgsettings}` with `debugtype=Serial`,
`debugport=1`, `baudrate=115200`, and the loader object is the only object that
would be changed in a later isolated test.

Serial KD needs a raw two-way byte stream: debugger traffic is not terminal
text, so zero bytes, binary framing and replies must reach UART RX. The current
16550-style COM1 is technically suitable; KD does not require a screen or WinPE
user mode. Polled access can work during early debugger setup; interrupt-driven
behavior is not a prerequisite for establishing the initial transport. Flow
control and baud must match the configured 115200 serial endpoint.

```text
KD_OVER_CURRENT_CROSVM_UART = CONDITIONAL
```

Condition: expose the already implemented `ttyS0` RX pipe to the VM owner as a
raw writable stream and prove byte-for-byte U-Boot echo first. Current AVF does
not meet that condition. KDNET, USB and 1394 do not supply a replacement in the
present VM: no configured supported NIC/debug path exists before Windows
network initialization, and no applicable USB/1394 debug device is present.

## Track 5 / 6 / 7 — host logs, service state and `/proc`

`adb shell` can see `android.system.virtualizationservice` in the service list,
`init.svc.virtualizationservice=running`, and process state through `ps`,
`/proc/<pid>/status`, `wchan`, thread names and cgroups. It cannot query a
`dumpsys android.system.virtualizationservice` implementation; the command
returns `Can't find service`. `dmesg` is denied.

Existing logcat contains crosvm-tagged device messages and Samsung `io_stats`
records that name crosvm PIDs. It can show crosvm warnings and a host process
that performed I/O, but it does not emit a stable per-VM Windows boot phase,
virtqueue count or GZVM exit reason. It is supporting evidence, not a primary
post-EBS boundary.

The already running Samsung Terminal VM demonstrates what shell can observe
without launching anything: its crosvm has `crosvm_vcpu0` through
`crosvm_vcpu7`, `virtio_blk`, `v_console`, `v_input`, `vhost_vsock`, and other
worker threads. That establishes an available future process-level signal for
a WinAVF crosvm PID, but says nothing by itself about guest instruction flow.

## Track 8 — Perfetto / atrace

The release device has `/system/bin/perfetto`, a registered `linux.ftrace` data
source, and normal trace categories `sched`, `irq`, `disk`, `binder_driver`,
`freq`, and others. `perfetto --help` explicitly accepts individual ftrace
records such as `sched/sched_switch`; `atrace --list_categories` exposes the
same standard categories. `adb shell` has group `readtracefs`.

The kernel also registers `kvm` and `geniezone` event groups, including
`kvm_entry`, `kvm_exit`, `kvm_mmio`, `kvm_userspace_exit`,
`geniezone/mtk_vcpu_exit`, and `geniezone/mtk_hypcall_*`. However, direct
reads of those event descriptors and enables are denied to shell. This audit
did not attempt a trace configuration, so it does not claim that Perfetto may
enable those restricted events.

The safe, established subset is standard scheduler/block/IRQ tracing:

* `sched/sched_switch` and `sched/sched_wakeup` can show whether the WinAVF
  crosvm process and named `crosvm_vcpu*`/virtio worker threads continue to be
  scheduled after the known `BES` boundary.
* `block/block_rq_issue` and `block/block_rq_complete` can show host block
  activity temporally correlated with the run, but not prove that a given
  request came from guest virtio-blk.
* `irq/irq_handler_entry` and `irq/irq_handler_exit` are host interrupts only;
  they cannot be assigned to an individual guest without a permitted GZVM/KVM
  event source.

Therefore `PERFETTO_AVF_TRACE = PARTIAL`: it is the first safe host observer,
but not a kernel-entry probe.

## Track 9 / 10 / 13 — crosvm and GenieZone telemetry

The local AVF source does create a Unix seqpacket crosvm control listener and
uses it for balloon statistics. Its `VmMetric` contains only start timestamp,
cumulative guest CPU time recorded before VM death, and RSS high-water mark;
exit reporting goes to internal stats collection. No public Java API returns
virtio-blk/GPU/vsock request counts, MSI counts, vCPU exit state, or a device
trace. The actual control listener is inherited as `/proc/self/fd/15` and its
service directory is inaccessible to shell.

`/dev/gzvm` exists with permissive DAC mode, and GZVM/GenieZone modules and
ftrace groups are present. This does not make a safe app API: SELinux and the
uninspected ioctl contract still control access. Per scope, no device open or
ioctl was attempted. There is no exposed read-only GZVM counter or debugfs node
visible to shell.

## Track 11 — Samsung Terminal

Terminal is an APEX privileged package (`com.android.virtualization.terminal`,
UID 10315) and its VM host runs in `u:r:virtualizationmanager:s0`; its crosvm
runs in `u:r:crosvm:s0`. The observed Terminal command line has separate
`--input multi-touch`, `--input keyboard`, `--input mouse`, and trackpad FDs.
This is Android UI -> crosvm virtio-input plumbing, not proof of a public serial
RX or debug service. It also had no `input=` parameter on its own serial
argument in the captured session.

The Terminal service is non-exported and the display/debug Binder paths remain
private to the platform SELinux domains. Its facilities cannot be reused by
WinAVF without a privilege change.

## Ranking and proposed next A/B

### BEST_CANDIDATE — host-only Perfetto liveness trace

This is the only candidate currently available without a guest/media change,
root, system modification or hidden API use. It is a one-run **host capture**,
not a Windows test modification.

Proposed mechanism, if separately authorized:

1. Start a bounded 45-second `adb shell perfetto` capture before launching the
   immutable WinAVF baseline, collecting `sched/sched_switch`,
   `sched/sched_wakeup`, `block/block_rq_issue`,
   `block/block_rq_complete`, `irq/irq_handler_entry`, and
   `irq/irq_handler_exit`.
2. Record the WinAVF crosvm PID and its thread names with read-only `ps -T` at
   launch, then correlate the trace with the raw serial `BES` timestamp and
   crosvm process lifetime.
3. Stop the bounded trace, pull it, and make no guest-media changes.

What it can prove: the host crosvm process survived or died; whether its vCPU
and device-worker threads were scheduled; whether host block/IRQ activity
continued during the run. What it cannot prove: `ntoskrnl` entry, a particular
virtio request, a guest instruction pointer, or a Windows driver state.

### SECOND_BEST_CANDIDATE — `adb shell` process/logcat observer

Bounded sampling of `ps -T`, `/proc/<pid>/status`, and filtered logcat can
independently show crosvm survival, named vCPU worker existence, and fatal/error
logs. It is simpler but lower resolution than Perfetto and cannot correlate
execution tightly enough to replace it.

### BLOCKED_CANDIDATES

* raw serial KD / bootdebug: blocked only by absent public UART RX;
* hidden console input FD: exists but requires non-public/TestApi access;
* crosvm control/stats socket: service-owned and inaccessible;
* KVM/GenieZone event trace: registered but direct shell access is denied;
* virtio queue/device statistics: no public runtime export;
* Terminal input/display channels: private platform SELinux path;
* KDNET/USB/1394 and EMS: no applicable early bidirectional device/path.

No proposed A/B was run. Permission is required before any Perfetto capture or
VM launch.

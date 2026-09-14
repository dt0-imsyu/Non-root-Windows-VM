# Shell crosvm GDB endpoint — runtime result — 2026-09-09

## Scope

This was the authorized bounded test of crosvm's documented `--gdb` endpoint
for a shell-created Windows raw VM. It was not Windows KD. The staged disk was
a new disposable clone of the immutable product baseline and was configured
`"writable": false`. No BCD, WIM, firmware, driver, Android app, or signed
Windows binary was modified.

## Verified input

| Item | Value |
|---|---|
| Baseline and staged-clone SHA-256 | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| Clone length | `9,126,805,504` bytes |
| U-Boot wrapper SHA-256 | `93EDA7C4BD54C33F85ADA6F05158C74EC6F5C3232F5CBA73846E5B442895F234` |
| VM shape | non-protected, 1 vCPU, 4096 MiB, `ttyS0`, read-only disk |
| Proposed endpoint | crosvm `--gdb 4567`, forwarded to host TCP `4567` |

## Result

Two creation attempts ended before crosvm or guest creation. The initial
request used `--gdb 4567`; the second added explicit `--debug full`, matching
the CLI help. Both received the exact VirtMgr error:

```text
Status(-8, EX_SERVICE_SPECIFIC): '-1: Can't use gdb with non-deguggable VMs'
```

For both attempts, `Running VMs: []`, serial was zero bytes, crosvm log was
empty, and no GDB client connected. There is consequently no PC/register,
vCPU-exit, IRQ/GIC, timer, WFI/WFE, or exception observation.

## Cleanup and classification

The ADB TCP forward and exact remote staging directory were removed. Product
baseline afterwards remained exactly
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`, no VM
remained, and hidden API policy was `null`. The local disposable clone at
`E:\winavf-shell-gdb-pc-clone-20260909.img` is retained as evidence only.

```text
SHELL_RAW_VM_GDB_REQUEST        = REJECTED_BY_VIRTMGR
SHELL_GUEST_GDB_PC_OBSERVER     = BLOCKED
WINDOWS_GUEST_EXECUTION          = NOT_STARTED
DIRECT_POST_EBS_WINDOWS_OBSERVABILITY = BLOCKED
```

The advertised crosvm GDB feature is unusable for this Samsung raw Windows
configuration, even with explicit full debug. Do not retry this shape. The
only remaining candidate is a supported product app configuration path that
sets `VirtualMachineAppConfig.CustomConfig.gdbPort`.

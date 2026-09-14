# Product Windows 1-vCPU versus host-topology A/B — 2026-09-13

## Question

Could the product VM's fixed single-vCPU topology explain the silent Windows
boundary after the already-proven `ExitBootServices()` return?

The historical Termux/QEMU Windows control used four vCPUs, whereas the
product AVF app normally requests `CPU_TOPOLOGY_ONE_CPU`.  This was a single
configuration-variable test; it did not infer that CPU count was the cause.

## Controlled change

Only the product app's `VirtualMachineConfig.setCpuTopology()` argument was
temporarily changed from `CPU_TOPOLOGY_ONE_CPU` to the framework's documented
`CPU_TOPOLOGY_MATCH_HOST` constant.  The app passed that request to AVF, which
created an eight-vCPU product VM.

Unchanged:

- immutable Windows raw image and all Windows media;
- EDK2 firmware bytes;
- BCD, WIM, drivers, and Android system state;
- PCI, RAM size, disk, console, GPU, and AVF custom-image configuration.

## Preconditions and rollback

The Android baseline image was hashed before launch and after VM removal:

```text
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

The installed product APK was saved before the test and restored afterwards.
Its SHA-256 before and after restoration was identical:

```text
043568B14989EC56233E1269F180474844E8B589FB065C9FA953CB5CED7D747E
```

The temporary host-topology APK SHA-256 was:

```text
E6078A06796AA636FF514D1191C32B4EB540082B736FB78B2FAFB362F8D1455F
```

`vm list` was empty after cleanup.

## Runtime evidence

Raw serial artifact:

`C:\Users\denis\MainProjects\win11ontab\build-logs\cpu-topology-ab-20260913\raw-serial-8vcpu.log`

The guest FDT and generated ACPI both reflected eight CPUs:

```text
AVF_GIC_FDT: ... redistributor @ 0x3FEF0000
ACPI_AUDIT GICC[0] uid=0 mpidr=0 flags=00000001 gicr=0
...
ACPI_AUDIT GICC[7] uid=7 mpidr=7 flags=00000001 gicr=0
ACPI_AUDIT GICR base=3FEF0000 range=100000
AVF_BDS_START_IMAGE \EFI\BOOT\BOOTAA64.EFI fs=0
ER
```

`ER` retains its established meaning in this product firmware: the original
`ExitBootServices()` returned successfully.  No later Windows, WinPE, or
user-mode signal occurred in the bounded run.

## Result

```text
AVF_HOST_CPU_TOPOLOGY_REQUEST       = PASS
PRODUCT_8VCPU_FDT_ACPI_CONTRACT     = PASS
PRODUCT_8VCPU_EXIT_BOOT_SERVICES    = PASS
PRODUCT_8VCPU_WINDOWS_POST_EBS      = NOT_CONFIRMED
SINGLE_VCPU_AS_FAST_WINDOWS_FIX     = REFUTED
```

This rules out the simple one-versus-many-vCPU explanation.  It does not rule
out a narrower Windows SMP/HAL defect, but no longer justifies speculative CPU
topology experiments.  The immutable one-vCPU product baseline remains the
active configuration.

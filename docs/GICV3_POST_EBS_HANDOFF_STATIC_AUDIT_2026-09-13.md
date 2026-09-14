# GICv3 post-EBS handoff static audit — 2026-09-13

## Question

After P6 established that firmware remains at EL1 across `ExitBootServices()`,
could EDK2's GICv3 teardown itself be a concrete common cause of the silent
Windows and Linux handoffs?

This was source/binary analysis only. No VM, media, BCD, firmware image, ACPI
table, or Android component was changed.

## Firmware behaviour

The exact current EDK2 GICv3 driver deliberately quiesces its own interrupt
state at EBS:

```text
ArmPkg/Drivers/ArmGicDxe/GicV3/ArmGicV3Dxe.c
GicV3ExitBootServicesEvent(), lines 567–584
  - disables registered sources
  - ArmGicV3DisableInterruptInterface()
  - ArmGicDisableDistributor()
```

The same driver documents this as normal shutdown behaviour and initializes
the GIC before EBS with affinity routing, Group-1 delivery, priority mask and
binary point:

```text
GicV3DxeInitialize(), lines 629–705
  ICC_SRE enabled for the current EL
  GICD.CTLR.ARE enabled
  ICC_BPR1_EL1 = 0x7
  ICC_PMR_EL1 = 0xff
  ICC_IGRPEN1_EL1 = 1
```

At EBS those values are deliberately no longer a firmware service contract.
The guest OS must initialize its own GIC state.

P1/P6 independently prove this expected quiescence in the actual VM: the
probe explicitly restores GICD affinity routing plus Group-1 and enables the
cached virtual PPI before its `WFI`; virtual PPI27 then wakes it successfully.
That proves the physical GIC delivery path can be re-established after EBS,
but does not imply an OS should inherit P1's state.

## Exact Windows binary evidence

The unmodified baseline WinPE kernel (`ntoskrnl.exe`, ARM64 26100.6584,
SHA-256 `C667739004D1186DACA2FD3FE7CCDE61394BC068F385B4BB8CD5364D3005A734`)
contains a complete GICv3 system-register control path. The direct AArch64
disassembly includes:

```text
0x1404ae514  MRS ICC_SRE_EL1
0x1404ae524  MSR ICC_SRE_EL1, x8
0x1404ae538  MRS ICC_CTLR_EL1
0x1404ae554  MSR ICC_IGRPEN1_EL1, x8
0x1404ae558  MSR ICC_PMR_EL1, x8
0x1404ae560  MSR ICC_BPR1_EL1, x8
```

It also contains reads/writes for `ICC_IAR1_EL1`, `ICC_EOIR1_EL1`,
`ICC_DIR_EL1` and `ICC_SGI1R_EL1`. `winload.efi` additionally contains an
EL2-only GIC SRE setup path guarded by its EL2 transition code; P6 shows the
firmware probe itself runs at EL1 and cannot establish whether that optional
winload path is later selected.

## Verdict

```text
EDK2_GICV3_EBS_QUIESCENCE          = EXPECTED
POST_EBS_GICV3_REARM_PLATFORM_PATH = PASS (P1/P6 evidence)
WINDOWS_GICV3_REINIT_CODE_PATH     = PASS (static)
FIRMWARE_GIC_HANDOFF_DEFECT         = NO_CONCRETE_DEFECT_FOUND
VALID_GIC_KEEP_ENABLED_A_B          = NOT_IDENTIFIED
```

The static evidence cannot prove that Windows reaches the shown kernel GIC
routine. It does show that a firmware patch preserving Group-1 or the
distributor across EBS would violate the established EDK2 ownership handoff
without a specific Windows requirement. Such an A/B is therefore not
authorized by the evidence.

## Next boundary

The physical `CNTP_*` branch and the GIC teardown branch are now both closed
as direct Windows fixes. Any next experiment requires a new concrete shared
post-EBS contract hypothesis, preferably based on the EL1 MMU/cache/vector
handoff rather than a random ACPI or GIC change.

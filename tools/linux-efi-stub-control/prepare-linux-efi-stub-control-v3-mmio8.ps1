[CmdletBinding()]
param()

# Elevated, disposable-only preparation of the direct Linux EFI-stub v3
# control.  This differs from the executed v2 control only in the Linux
# earlycon accessor: uart8250,mmio (8-bit) instead of uart8250,mmio32.
# It never writes Android storage or starts a VM.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = 'C:\Users\denis\MainProjects\win11ontab'
$logs = Join-Path $root 'build-logs\linux-efi-stub-control-v3-mmio8-20260911'
$vhd = 'D:\winavf-linux-efi-stub-control-v3-mmio8-work-fixed.vhd'
$raw = 'E:\winavf-linux-efi-stub-control-v3-mmio8-candidate.img'
$launcher = Join-Path $root 'firmware-work\edk2\Build\ArmVirtKvmTool-AARCH64\DEBUG_GCC5\AARCH64\ArmPkg\Application\AvfLinuxEfiStubProbe\AvfLinuxEfiStubProbe\DEBUG\AvfLinuxEfiStubProbe.efi'
$launcherSha256 = 'F3FEE2904150D53D309D220D3BF4D0F7597B81B63964A496DAB0A51D8B5C1DEE'

& (Join-Path $here 'materialize-linux-efi-stub-control.ps1') `
    -LauncherEfi $launcher `
    -ExpectedLauncherSha256 $launcherSha256 `
    -VhdPath $vhd `
    -OutputRaw $raw `
    -ReportPath (Join-Path $logs 'materialize-report.txt')
& (Join-Path $here 'audit-linux-efi-stub-control.ps1') `
    -CandidateRaw $raw `
    -VhdPath $vhd `
    -ExpectedLauncherSha256 $launcherSha256 `
    -ExpectedEarlycon 'earlycon=uart8250,mmio,0x3f8' `
    -ReportPath (Join-Path $logs 'offline-audit.txt')

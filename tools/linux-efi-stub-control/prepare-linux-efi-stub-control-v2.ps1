[CmdletBinding()]
param()

# Re-materialize the same direct EFI-stub candidate only after the v1 raw-copy
# cache gap was found.  Distinct output names preserve every v1 artifact.  The
# underlying materializer now has a mandatory FAT32 detach/re-attach flush
# before reading virtual disk sectors into the raw candidate.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = 'C:\Users\denis\MainProjects\win11ontab'
$logs = Join-Path $root 'build-logs\linux-efi-stub-control-v2-20260911'
$vhd = 'D:\winavf-linux-efi-stub-control-v2-work-fixed.vhd'
$raw = 'E:\winavf-linux-efi-stub-control-v2-candidate.img'

& (Join-Path $here 'materialize-linux-efi-stub-control.ps1') `
    -VhdPath $vhd `
    -OutputRaw $raw `
    -ReportPath (Join-Path $logs 'materialize-report.txt')
& (Join-Path $here 'audit-linux-efi-stub-control.ps1') `
    -CandidateRaw $raw `
    -VhdPath $vhd `
    -ReportPath (Join-Path $logs 'offline-audit.txt')

[CmdletBinding()]
param(
    [string] $ArtifactDir = ('C:\Users\denis\MainProjects\win11ontab\build-logs\linux-efi-stub-runtime-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [int] $DurationSeconds = 100,
    [string] $AdbPath = 'C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe'
)

# One bounded product-topology execution of the already-audited direct
# Linux EFI-stub candidate.  The common runner validates the immutable Android
# baseline before applying the patch, captures raw serial, stops the app, then
# requires the launcher's exact transactional rollback report and re-hashes
# the baseline.  No second launch is performed.
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot '..\linux-acpi-control\run-linux-acpi-control.ps1') `
    -PatchPath 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-efi-stub-control-20260911\linux-efi-stub-control.patch' `
    -ExpectedPatchSha256 '9A99672579EFE963170B6129E9B645655E0E676B43DFAC0B5A1136BDD5B3C82B' `
    -ArtifactDir $ArtifactDir `
    -DurationSeconds $DurationSeconds `
    -AdbPath $AdbPath

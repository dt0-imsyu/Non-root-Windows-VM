[CmdletBinding()]
param(
    [string] $ArtifactDir = ('C:\Users\denis\MainProjects\win11ontab\build-logs\linux-efi-stub-runtime-v3-mmio8-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [int] $DurationSeconds = 100,
    [string] $AdbPath = 'C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe'
)

# Exactly one bounded runtime for the v3 earlycon accessor A/B.  It uses the
# existing common runner for Android baseline verification, patch staging,
# serial capture, VM stop and exact transactional rollback.
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot '..\linux-acpi-control\run-linux-acpi-control.ps1') `
    -PatchPath 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-efi-stub-control-v3-mmio8-20260911\linux-efi-stub-control-v3-mmio8.patch' `
    -ExpectedPatchSha256 '2E0D3C876D67A45BB2B42086821F6EE840645674D2B41129B9EF7A493E001182' `
    -ArtifactDir $ArtifactDir `
    -DurationSeconds $DurationSeconds `
    -AdbPath $AdbPath

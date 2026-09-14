[CmdletBinding()]
param(
    [string] $ArtifactDir = ('C:\Users\denis\MainProjects\win11ontab\build-logs\linux-efi-stub-runtime-v2-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [int] $DurationSeconds = 100,
    [string] $AdbPath = 'C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe'
)

# Exactly one runtime after the v2 candidate's detached/re-attached raw copy
# and transactional overlay verification.  Delegate lifecycle, Android
# baseline verification, raw serial capture and transactional rollback to the
# already-proven common runner.
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot '..\linux-acpi-control\run-linux-acpi-control.ps1') `
    -PatchPath 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-efi-stub-control-v2-20260911\linux-efi-stub-control-v2.patch' `
    -ExpectedPatchSha256 'C00675252512D82D2D14D4266BC4BA388A50F94A82A9BA345068BB0DAC33DE57' `
    -ArtifactDir $ArtifactDir `
    -DurationSeconds $DurationSeconds `
    -AdbPath $AdbPath

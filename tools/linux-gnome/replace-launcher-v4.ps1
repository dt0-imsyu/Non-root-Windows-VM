$ErrorActionPreference = 'Stop'

# This creates V4 from the existing disposable Ubuntu VHD.  It replaces only
# EFI\BOOT\BOOTAA64.EFI with the launcher rebuilt for the root \CASPER layout.
$vhd = 'D:\winavf-ubuntu-gnome-24.04.5-v2-work-fixed.vhd'
$launcher = 'C:\Users\denis\MainProjects\win11ontab\firmware-work\edk2\Build\ArmVirtKvmTool-AARCH64\DEBUG_GCC5\AARCH64\ArmPkg\Application\AvfUbuntuEfiStubProbe\AvfUbuntuEfiStubProbe\DEBUG\AvfUbuntuEfiStubProbe.efi'
$raw = 'E:\winavf-ubuntu-gnome-24.04.5-v8-fdt-candidate.img'
$report = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-gnome-20260919\replace-launcher-v8-fdt-report.txt'
$expectedBytes = [int64]9126805504
$expectedOffset = [int64]1048576
$expectedPartitionBytes = [int64]9125740032

function Get-Sha256([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }
function Assert-Admin {
  $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script from an elevated PowerShell.' }
}
function Export-Raw([string]$Source,[string]$Destination) {
  $input = [IO.File]::Open($Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  $output = [IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try {
    $buffer = [byte[]]::new(8MB); [int64]$copied = 0
    while ($copied -lt $expectedBytes) {
      $want = [int][Math]::Min([int64]$buffer.Length, $expectedBytes - $copied)
      $got = $input.Read($buffer,0,$want)
      if ($got -le 0) { throw 'Unexpected end while reading temporary VHD.' }
      $output.Write($buffer,0,$got); $copied += $got
    }
    $output.Flush($true)
  } finally { $output.Dispose(); $input.Dispose() }
}

Assert-Admin
foreach ($path in @($vhd,$launcher)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required file: $path" } }
foreach ($path in @($raw,$report)) { if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite: $path" } }
$launcherHash = Get-Sha256 $launcher
$mounted = $false
try {
  Mount-DiskImage -ImagePath $vhd -NoDriveLetter; $mounted = $true
  $disk = Get-DiskImage -ImagePath $vhd | Get-Disk
  if ($disk.Size -ne $expectedBytes) { throw 'Temporary VHD size mismatch.' }
  $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq $expectedOffset -and $_.Size -eq $expectedPartitionBytes }
  if (@($part).Count -ne 1) { throw 'Expected FAT32 partition geometry missing.' }
  $volume = $part | Get-Volume
  if ($volume.FileSystem -ne 'FAT32') { throw "Expected FAT32, found $($volume.FileSystem)." }
  if (-not $volume.DriveLetter) {
    Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AssignDriveLetter
    $volume = Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber | Get-Volume
  }
  if (-not $volume.DriveLetter) { throw 'Could not obtain a drive letter for the temporary VHD.' }
  $root = "$($volume.DriveLetter):"
  foreach ($required in @((Join-Path $root 'CASPER\VMLINUZ'),(Join-Path $root 'CASPER\INITRD'),(Join-Path $root 'CASPER\SHA256SUMS'),(Join-Path $root 'EFI\BOOT\BOOTAA64.EFI'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "V3 root-CASPER precondition missing: $required" }
  }
  Copy-Item -LiteralPath $launcher -Destination (Join-Path $root 'EFI\BOOT\BOOTAA64.EFI') -Force
  $onDiskHash = Get-Sha256 (Join-Path $root 'EFI\BOOT\BOOTAA64.EFI')
  if ($onDiskHash -ne $launcherHash) { throw 'EFI launcher copy verification failed.' }
  Dismount-DiskImage -ImagePath $vhd; $mounted = $false
  Mount-DiskImage -ImagePath $vhd -NoDriveLetter; $mounted = $true
  $disk = Get-DiskImage -ImagePath $vhd | Get-Disk
  Export-Raw "\\.\PhysicalDrive$($disk.Number)" $raw
  @(
    'RESULT=PASS', 'CHANGE=Only EFI\\BOOT\\BOOTAA64.EFI replaced; root CASPER payload retained',
    "VHD_PATH=$vhd", "RAW_PATH=$raw", "RAW_BYTES=$((Get-Item -LiteralPath $raw).Length)",
    "RAW_SHA256=$(Get-Sha256 $raw)", "EFI_LAUNCHER_SHA256=$launcherHash"
  ) | Set-Content -LiteralPath $report -Encoding utf8
  Get-Content -LiteralPath $report
} finally { if ($mounted) { Dismount-DiskImage -ImagePath $vhd -ErrorAction SilentlyContinue } }

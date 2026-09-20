[CmdletBinding()]
param(
  [string] $BaselineRaw = 'E:\winavf-a3-append-only-runtime.img',
  [string] $UbuntuIso = 'E:\winavf-linux-gnome-20260919\ubuntu-24.04.5-desktop-arm64.iso',
  [string] $LauncherEfi = 'C:\Users\denis\MainProjects\win11ontab\firmware-work\edk2\Build\ArmVirtKvmTool-AARCH64\DEBUG_GCC5\AARCH64\ArmPkg\Application\AvfUbuntuEfiStubProbe\AvfUbuntuEfiStubProbe\DEBUG\AvfUbuntuEfiStubProbe.efi',
  [string] $VhdPath = 'D:\winavf-ubuntu-gnome-24.04.5-work-fixed.vhd',
  [string] $OutputRaw = 'E:\winavf-ubuntu-gnome-24.04.5-candidate.img',
  [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-gnome-20260919\materialize-report.txt'
)

# Elevated disposable-media workflow.  It creates a fixed VHD from the exact
# Windows baseline, clears only that VHD's old boot payload, and uses the
# normal Windows FAT32 driver to copy Ubuntu's published casper layout.
# It does not write Android storage, firmware, BCD, WIM, or the baseline raw.
$ErrorActionPreference = 'Stop'
$expectedBaseline = '2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7'
$expectedBytes = [int64]9126805504
$expectedOffset = [int64]1048576
$expectedPartitionBytes = [int64]9125740032
$expectedIso = '2BE09CA883921BFF6D8E6B0BFBAFD13E32436553B7086F33BCE3A4C5BAD8BD14'
$expectedLauncher = '21D1E844E6C3C1EB3797EC08551F6DEA6461F60663147C6566AF768DD27824B5'

function Get-Sha256([string] $Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }
function Assert-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run from an elevated PowerShell window.' }
}
function Copy-ExactRaw([string] $Source, [string] $Destination, [int64] $Bytes) {
  $input = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  $output = [IO.File]::Open($Destination, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
  try {
    $buffer = [byte[]]::new(8MB); [int64]$copied = 0
    while ($copied -lt $Bytes) {
      $want = [int][Math]::Min([int64]$buffer.Length, $Bytes - $copied)
      $read = $input.Read($buffer, 0, $want)
      if ($read -le 0) { throw 'Unexpected source EOF.' }
      $output.Write($buffer, 0, $read); $copied += $read
    }
    $output.Flush($true)
  } finally { $output.Dispose(); $input.Dispose() }
}
function Copy-PhysicalRaw([string] $PhysicalDrive, [string] $Destination, [int64] $Bytes) {
  $input = [IO.File]::Open($PhysicalDrive, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
  $output = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try {
    $buffer = [byte[]]::new(8MB); [int64]$copied = 0
    while ($copied -lt $Bytes) {
      $want = [int][Math]::Min([int64]$buffer.Length, $Bytes - $copied)
      $read = $input.Read($buffer, 0, $want)
      if ($read -le 0) { throw 'Unexpected VHD EOF.' }
      $output.Write($buffer, 0, $read); $copied += $read
    }
    $output.Flush($true)
  } finally { $output.Dispose(); $input.Dispose() }
}

Assert-Admin
$baseline = (Resolve-Path -LiteralPath $BaselineRaw).Path
$iso = (Resolve-Path -LiteralPath $UbuntuIso).Path
$launcher = (Resolve-Path -LiteralPath $LauncherEfi).Path
if ((Get-Item -LiteralPath $baseline).Length -ne $expectedBytes -or (Get-Sha256 $baseline) -ne $expectedBaseline) { throw 'Exact immutable baseline mismatch.' }
if ((Get-Sha256 $iso) -ne $expectedIso) { throw 'Official Ubuntu ISO SHA-256 mismatch.' }
if ((Get-Sha256 $launcher) -ne $expectedLauncher) { throw 'Ubuntu EFI launcher SHA-256 mismatch.' }
foreach ($path in @($VhdPath, $OutputRaw, $ReportPath)) { if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite: $path" } }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null

$vhdAttached = $false
$isoAttached = $false
$diskpartFile = Join-Path $env:TEMP ('winavf-ubuntu-gnome-' + [Guid]::NewGuid().ToString('N') + '.txt')
try {
  @"
create vdisk file="$VhdPath" maximum=$([int64]($expectedBytes / 1MB)) type=fixed
select vdisk file="$VhdPath"
attach vdisk
"@ | Set-Content -LiteralPath $diskpartFile -Encoding ascii
  & "$env:SystemRoot\System32\diskpart.exe" /s $diskpartFile
  if ($LASTEXITCODE -ne 0) { throw 'DiskPart fixed-VHD creation failed.' }
  $vhdAttached = $true
  $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
  if ($disk.Size -ne $expectedBytes) { throw 'Unexpected temporary VHD size.' }
  Copy-ExactRaw $baseline ("\\.\PhysicalDrive$($disk.Number)") $expectedBytes
  Update-Disk -Number $disk.Number
  $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq $expectedOffset -and $_.Size -eq $expectedPartitionBytes }
  if (@($part).Count -ne 1) { throw 'Expected disposable FAT32 geometry not found.' }
  $volume = $part | Get-Volume
  if ($volume.FileSystem -ne 'FAT32') { throw "Expected FAT32, got $($volume.FileSystem)." }
  if (-not $volume.DriveLetter) {
    Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AssignDriveLetter
    $volume = Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber | Get-Volume
  }
  if (-not $volume.DriveLetter) { throw 'Could not obtain temporary VHD drive letter.' }
  $root = "$($volume.DriveLetter):"

  # Targets have been identified by the temporary VHD path, disk number, and
  # exact baseline GPT geometry above.  These deletes never target the host or
  # the immutable raw: they only free space on the disposable FAT32 VHD.
  foreach ($relative in @('BOOT', 'EFI\MICROSOFT', 'SOURCES', 'SUPPORT', 'BOOTNXT')) {
    $target = Join-Path $root $relative
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
  }
  foreach ($relative in @('AUTORUN.INF', 'SETUP.EXE')) {
    $target = Join-Path $root $relative
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
  }
  New-Item -ItemType Directory -Force -Path (Join-Path $root 'EFI\BOOT'), (Join-Path $root 'UBUNTU\CASPER'), (Join-Path $root '.disk') | Out-Null
  Set-Volume -DriveLetter $volume.DriveLetter -NewFileSystemLabel 'Ubuntu 24.04.5 L'

  Mount-DiskImage -ImagePath $iso -Access ReadOnly -NoDriveLetter
  $isoAttached = $true
  $sourceVolume = Get-Volume | Where-Object { $_.FileSystem -eq 'CDFS' -and $_.FileSystemLabel -eq 'Ubuntu 24.04.5 L' } | Select-Object -First 1
  if ($null -eq $sourceVolume) { throw 'Mounted Ubuntu CDFS volume was not found.' }
  $sourceRoot = $sourceVolume.Path
  foreach ($required in @('casper\vmlinuz', 'casper\initrd', 'casper\minimal.squashfs', 'casper\minimal.standard.live.squashfs', 'casper\minimal.standard.squashfs', '.disk\info')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $required))) { throw "Official ISO asset missing: $required" }
  }
  Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'casper') -Force |
    Copy-Item -Destination (Join-Path $root 'UBUNTU\CASPER') -Recurse -Force
  Get-ChildItem -LiteralPath (Join-Path $sourceRoot '.disk') -Force |
    Copy-Item -Destination (Join-Path $root '.disk') -Recurse -Force
  Copy-Item -LiteralPath $launcher -Destination (Join-Path $root 'EFI\BOOT\BOOTAA64.EFI') -Force
  Dismount-DiskImage -ImagePath $iso
  $isoAttached = $false

  # Flush FAT32 writes before using the virtual disk as a raw-sector source.
  Dismount-DiskImage -ImagePath $VhdPath
  $vhdAttached = $false
  Mount-DiskImage -ImagePath $VhdPath | Out-Null
  $vhdAttached = $true
  $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
  if ($disk.Size -ne $expectedBytes) { throw 'VHD size changed across flush/re-attach.' }
  $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq $expectedOffset -and $_.Size -eq $expectedPartitionBytes }
  if (@($part).Count -ne 1) { throw 'Expected geometry changed across flush/re-attach.' }
  Copy-PhysicalRaw ("\\.\PhysicalDrive$($disk.Number)") $OutputRaw $expectedBytes

  @(
    'RESULT=PASS', "BASELINE_RAW=$baseline", "BASELINE_SHA256=$expectedBaseline",
    "UBUNTU_ISO=$iso", "UBUNTU_ISO_SHA256=$expectedIso", "LAUNCHER_EFI=$launcher", "LAUNCHER_SHA256=$expectedLauncher",
    'PAYLOAD=casper plus .disk copied through Windows FAT32 driver', "VHD_PATH=$VhdPath", "RAW_PATH=$OutputRaw",
    "RAW_BYTES=$((Get-Item -LiteralPath $OutputRaw).Length)", "RAW_SHA256=$(Get-Sha256 $OutputRaw)",
    "PARTITION_OFFSET=$($part.Offset)", "PARTITION_BYTES=$($part.Size)",
    'NEXT=Run offline audit only. Do not copy to Android or launch a VM.'
  ) | Set-Content -LiteralPath $ReportPath -Encoding utf8
  Get-Content -LiteralPath $ReportPath
}
finally {
  if ($isoAttached) { Dismount-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue }
  if ($vhdAttached) { Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $diskpartFile -Force -ErrorAction SilentlyContinue
}

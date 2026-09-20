[CmdletBinding()]
param(
  [string] $VhdPath = 'D:\winavf-ubuntu-gnome-24.04.5-work-fixed.vhd',
  [string] $RawPath = 'E:\winavf-ubuntu-gnome-24.04.5-candidate.img',
  [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-gnome-20260919\audit-report.txt',
  [string] $ExpectedLauncher = '21D1E844E6C3C1EB3797EC08551F6DEA6461F60663147C6566AF768DD27824B5'
)

# Read-only audit of the newly materialized, disposable Ubuntu GNOME media.
$ErrorActionPreference = 'Stop'
$expectedBytes = [int64]9126805504
$expectedOffset = [int64]1048576
$expectedPartitionBytes = [int64]9125740032
$expectedLauncher = $ExpectedLauncher.ToUpperInvariant()
function Get-Sha256([string] $Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }

foreach ($path in @($VhdPath, $RawPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing candidate artifact: $path" } }
if ((Get-Item -LiteralPath $RawPath).Length -ne $expectedBytes) { throw 'Raw candidate length mismatch.' }
if (Test-Path -LiteralPath $ReportPath) { throw "Refusing to overwrite: $ReportPath" }

$mounted = $false
try {
  Mount-DiskImage -ImagePath $VhdPath -Access ReadOnly -NoDriveLetter
  $mounted = $true
  $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
  if ($disk.Size -ne $expectedBytes) { throw 'VHD geometry mismatch.' }
  $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq $expectedOffset -and $_.Size -eq $expectedPartitionBytes }
  if (@($part).Count -ne 1) { throw 'Expected FAT32 partition geometry missing.' }
  $volume = $part | Get-Volume
  if ($volume.FileSystem -ne 'FAT32') { throw 'Unexpected filesystem type.' }
  if (-not $volume.DriveLetter) {
    Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AssignDriveLetter
    $volume = Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber | Get-Volume
  }
  if (-not $volume.DriveLetter) { throw 'No drive letter for read-only VHD audit.' }
  $root = "$($volume.DriveLetter):"
  $bootaa = Join-Path $root 'EFI\BOOT\BOOTAA64.EFI'
  $casper = Join-Path $root 'CASPER'
  foreach ($required in @($bootaa, (Join-Path $casper 'VMLINUZ'), (Join-Path $casper 'INITRD'), (Join-Path $casper 'MINIMAL.SQUASHFS'), (Join-Path $casper 'MINIMAL.STANDARD.LIVE.SQUASHFS'), (Join-Path $casper 'MINIMAL.STANDARD.SQUASHFS'), (Join-Path $casper 'SHA256SUMS'), (Join-Path $root '.disk\info'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required Ubuntu payload missing: $required" }
  }
  if ((Get-Sha256 $bootaa) -ne $expectedLauncher) { throw 'EFI launcher hash mismatch.' }

  # The ISO supplies a complete SHA256SUMS list for every casper layer.  Check
  # all listed images from the VHD after a detach/re-attach boundary.
  $checked = 0
  foreach ($line in Get-Content -LiteralPath (Join-Path $casper 'SHA256SUMS')) {
    if ($line -match '^([0-9a-fA-F]{64}) \*(.+)$') {
      $expected = $matches[1].ToUpperInvariant(); $name = $matches[2]
      $actual = Get-Sha256 (Join-Path $casper $name)
      if ($actual -ne $expected) { throw "Casper payload hash mismatch: $name" }
      $checked++
    }
  }
  if ($checked -lt 20) { throw 'Incomplete casper SHA256SUMS audit.' }
  $chkdsk = (& "$env:SystemRoot\System32\chkdsk.exe" "$($volume.DriveLetter):" 2>&1 | Out-String).TrimEnd()
  if ($LASTEXITCODE -ne 0) { throw "CHKDSK reported a filesystem error (exit $LASTEXITCODE)." }
  $rawHash = Get-Sha256 $RawPath
  @(
    'RESULT=PASS', "RAW_PATH=$RawPath", "RAW_BYTES=$((Get-Item -LiteralPath $RawPath).Length)", "RAW_SHA256=$rawHash",
    "VHD_PATH=$VhdPath", "VHD_DISK=$($disk.Number)", "PARTITION_OFFSET=$($part.Offset)", "PARTITION_BYTES=$($part.Size)",
    'FILESYSTEM=FAT32', "LABEL=$($volume.FileSystemLabel)", 'EFI_LAUNCHER_ARM64=PASS', "EFI_LAUNCHER_SHA256=$expectedLauncher",
    "CASPER_SHA256SUMS_FILES=$checked", 'CASPER_PAYLOAD=PASS', 'CHKDSK=PASS', '', '--- CHKDSK ---', $chkdsk,
    'NEXT=Candidate is ready for a separate Android staging/launch decision.'
  ) | Set-Content -LiteralPath $ReportPath -Encoding utf8
  Get-Content -LiteralPath $ReportPath
}
finally { if ($mounted) { Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue } }

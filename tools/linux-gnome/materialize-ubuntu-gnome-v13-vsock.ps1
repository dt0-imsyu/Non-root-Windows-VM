[CmdletBinding()]
param(
  [string] $SourceRaw = 'E:\winavf-ubuntu-gnome-24.04.5-v10-fdtclient-cpu0-candidate.img',
  [string] $VhdPath = 'D:\winavf-ubuntu-gnome-24.04.5-v13-vsock-work-fixed.vhd',
  [string] $PatchedInitrd = 'C:\Users\denis\MainProjects\win11ontab\build-logs\ubuntu-gnome-vsock\initrd-with-winavf-vsock',
  [string] $OutputRaw = 'E:\winavf-ubuntu-gnome-24.04.5-v13-vsock-candidate.img',
  [string] $PatchPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\ubuntu-gnome-v13-vsock\ubuntu-gnome-v13-vsock-firmware.patch',
  [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\ubuntu-gnome-v13-vsock\materialize-and-audit-report.txt'
)

# This is deliberately a single-file replacement on a new fixed VHD.  The
# source is a disposable Ubuntu raw image; the immutable Windows medium is
# neither opened for writing nor used as an input.
$ErrorActionPreference = 'Stop'
$expectedSourceHash = 'FB201BABDD0E309D5177D683387495D058ACF910BAAEF8733DCB944CA92E569A'
$expectedBytes = [int64]9126805504
$expectedOffset = [int64]1048576
$expectedPartitionBytes = [int64]9125740032
$firmwareFd = 'C:\Users\denis\MainProjects\win11ontab\firmware-work\edk2\artifacts\KVMTOOL_EFI-ubuntu-fdt-handoff-v11.fd'
$expectedFirmwareHash = '7162202A2ED14C6BE3433915CB5786D9A41E3722647E40AA3CFEF29720D14963'
$patchBuilder = Join-Path (Split-Path -Parent $PSScriptRoot) 'uefi-serial-input\new-firmware-range-patch.ps1'

function Hash([string] $path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant() }
function Assert-Admin {
  $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run from an elevated PowerShell window.' }
}
function Copy-ExactRaw([string] $source, [string] $destination, [int64] $bytes) {
  $input = [IO.File]::Open($source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  $output = [IO.File]::Open($destination, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
  try {
    $buffer = New-Object byte[] 8MB; [int64] $done = 0
    while ($done -lt $bytes) {
      $want = [int][Math]::Min([int64]$buffer.Length, $bytes - $done)
      $read = $input.Read($buffer, 0, $want)
      if ($read -le 0) { throw 'Unexpected disposable source EOF.' }
      $output.Write($buffer, 0, $read); $done += $read
    }
    $output.Flush($true)
  } finally { $output.Dispose(); $input.Dispose() }
}
function Export-Raw([string] $source, [string] $destination, [int64] $bytes) {
  $input = [IO.File]::Open($source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
  $output = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try {
    $buffer = New-Object byte[] 8MB; [int64] $done = 0
    while ($done -lt $bytes) {
      $want = [int][Math]::Min([int64]$buffer.Length, $bytes - $done)
      $read = $input.Read($buffer, 0, $want)
      if ($read -le 0) { throw 'Unexpected temporary VHD EOF.' }
      $output.Write($buffer, 0, $read); $done += $read
    }
    $output.Flush($true)
  } finally { $output.Dispose(); $input.Dispose() }
}
function Get-ExpectedVolume([int] $diskNumber) {
  $part = Get-Partition -DiskNumber $diskNumber | Where-Object { $_.Offset -eq $expectedOffset -and $_.Size -eq $expectedPartitionBytes }
  if (@($part).Count -ne 1) { throw 'Temporary VHD GPT geometry does not match the disposable source.' }
  $volume = $part | Get-Volume
  if ($volume.FileSystem -ne 'FAT32') { throw "Expected FAT32, got $($volume.FileSystem)." }
  if (-not $volume.DriveLetter) {
    Add-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $part.PartitionNumber -AssignDriveLetter
    $volume = Get-Partition -DiskNumber $diskNumber -PartitionNumber $part.PartitionNumber | Get-Volume
  }
  if (-not $volume.DriveLetter) { throw 'Could not obtain a temporary VHD drive letter.' }
  return @{ Partition = $part; Volume = $volume; Root = "$($volume.DriveLetter):" }
}

Assert-Admin
foreach ($path in @($SourceRaw, $PatchedInitrd, $firmwareFd, $patchBuilder)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required input: $path" }
}
foreach ($path in @($VhdPath, $OutputRaw, $PatchPath, $ReportPath)) {
  if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite: $path" }
}
if ((Get-Item -LiteralPath $SourceRaw).Length -ne $expectedBytes -or (Hash $SourceRaw) -ne $expectedSourceHash) { throw 'Exact disposable V10 source hash mismatch.' }
if ((Get-Item -LiteralPath $PatchedInitrd).Length -le 80MB) { throw 'Patched initrd is unexpectedly small.' }
if ((Get-Item -LiteralPath $firmwareFd).Length -ne 2MB -or (Hash $firmwareFd) -ne $expectedFirmwareHash) { throw 'V11 FDT firmware artifact hash mismatch.' }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath), (Split-Path -Parent $PatchPath) | Out-Null

$mounted = $false
$diskpartFile = Join-Path $env:TEMP ('winavf-ubuntu-v13-vsock-' + [Guid]::NewGuid().ToString('N') + '.txt')
try {
  @"
create vdisk file="$VhdPath" maximum=$([int64]($expectedBytes / 1MB)) type=fixed
select vdisk file="$VhdPath"
attach vdisk
"@ | Set-Content -LiteralPath $diskpartFile -Encoding ascii
  & "$env:SystemRoot\System32\diskpart.exe" /s $diskpartFile
  if ($LASTEXITCODE -ne 0) { throw 'Fixed VHD creation failed.' }
  $mounted = $true
  $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
  if ($disk.Size -ne $expectedBytes) { throw 'Temporary VHD has unexpected size.' }
  Copy-ExactRaw $SourceRaw "\\.\PhysicalDrive$($disk.Number)" $expectedBytes
  Update-Disk -Number $disk.Number
  $state = Get-ExpectedVolume $disk.Number
  $initrdPath = Join-Path $state.Root 'CASPER\INITRD'
  $bootaaPath = Join-Path $state.Root 'EFI\BOOT\BOOTAA64.EFI'
  $kernelPath = Join-Path $state.Root 'CASPER\VMLINUZ'
  foreach ($path in @($initrdPath, $bootaaPath, $kernelPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "V10 source payload missing: $path" } }
  $oldInitrdHash = Hash $initrdPath; $bootaaHash = Hash $bootaaPath; $kernelHash = Hash $kernelPath; $newInitrdHash = Hash $PatchedInitrd
  Copy-Item -LiteralPath $PatchedInitrd -Destination $initrdPath -Force
  if ((Hash $initrdPath) -ne $newInitrdHash) { throw 'Written CASPER\\INITRD hash mismatch.' }
  if ((Hash $bootaaPath) -ne $bootaaHash -or (Hash $kernelPath) -ne $kernelHash) { throw 'Unexpected change outside CASPER\\INITRD.' }
  $check = (& "$env:SystemRoot\System32\chkdsk.exe" "$($state.Volume.DriveLetter):" 2>&1) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "CHKDSK reported a FAT32 error: $check" }

  # Flush Windows' normal FAT32 writes before treating the VHD as a sector source.
  Dismount-DiskImage -ImagePath $VhdPath; $mounted = $false
  Mount-DiskImage -ImagePath $VhdPath -NoDriveLetter | Out-Null; $mounted = $true
  $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
  if ($disk.Size -ne $expectedBytes) { throw 'Temporary VHD size changed after flush.' }
  $state = Get-ExpectedVolume $disk.Number
  if ((Hash (Join-Path $state.Root 'CASPER\INITRD')) -ne $newInitrdHash) { throw 'Post-flush INITRD hash mismatch.' }
  if ((Hash (Join-Path $state.Root 'EFI\BOOT\BOOTAA64.EFI')) -ne $bootaaHash -or (Hash (Join-Path $state.Root 'CASPER\VMLINUZ')) -ne $kernelHash) { throw 'Post-flush non-initrd hash mismatch.' }
  Export-Raw "\\.\PhysicalDrive$($disk.Number)" $OutputRaw $expectedBytes
  $candidateHash = Hash $OutputRaw
  & $patchBuilder -BaselineRaw $OutputRaw -ExpectedBaselineSha256 $candidateHash -FirmwareFd $firmwareFd -PatchPath $PatchPath -ReportPath (Join-Path (Split-Path -Parent $ReportPath) 'firmware-patch-report.txt')
  if ($LASTEXITCODE -ne 0) { throw 'V13 reversible FDT patch build failed.' }
  @(
    'RESULT=PASS',
    "SOURCE_RAW=$SourceRaw", "SOURCE_SHA256=$expectedSourceHash", "SOURCE_INITRD_SHA256=$oldInitrdHash",
    "PATCHED_INITRD_SHA256=$newInitrdHash", "BOOTAA64_EFI_SHA256_UNCHANGED=$bootaaHash", "VMLINUZ_SHA256_UNCHANGED=$kernelHash",
    'CHANGE=Only CASPER\\INITRD replaced through Windows FAT32 driver on temporary VHD',
    "VHD_PATH=$VhdPath", "VHD_DISK_NUMBER=$($disk.Number)", "RAW_PATH=$OutputRaw", "RAW_BYTES=$((Get-Item -LiteralPath $OutputRaw).Length)", "RAW_SHA256=$candidateHash",
    "PARTITION_OFFSET=$($state.Partition.Offset)", "PARTITION_BYTES=$($state.Partition.Size)", 'FAT32_CHKDSK=PASS',
    "FIRMWARE_PATCH=$PatchPath", "FIRMWARE_PATCH_SHA256=$(Hash $PatchPath)", "FIRMWARE_PATCH_BYTES=$((Get-Item -LiteralPath $PatchPath).Length)",
    'NEXT=New Ubuntu-only candidate is offline-ready. Stage only this raw and matching patch before one Linux vsock runtime.'
  ) | Set-Content -LiteralPath $ReportPath -Encoding utf8
  Get-Content -LiteralPath $ReportPath
}
finally {
  if ($mounted) { Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $diskpartFile -Force -ErrorAction SilentlyContinue
}

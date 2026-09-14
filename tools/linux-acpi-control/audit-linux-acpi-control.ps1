[CmdletBinding()]
param(
    [string] $CandidateRaw = 'E:\winavf-linux-acpi-control-bookworm-candidate.img',
    [string] $VhdPath = 'D:\winavf-linux-acpi-control-work-fixed.vhd',
    [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-acpi-control-20260911\offline-audit.txt'
)

# Elevated offline audit only. No Android action, VM run, formatting, or manual
# FAT edits. The VHD is the exact source read sector-for-sector into CandidateRaw.
$ErrorActionPreference = 'Stop'
$expectedBytes = [int64]9126805504
$expectedOffset = [int64]1048576
$expectedPartitionBytes = [int64]9125740032
$expectedGrub = '8E13D190B10BBDA24974DEE5D1B0BE4BA6207FB1FF19AA4465257A945A378B91'
$expectedLinux = '84B9C190BB4589C4A9527E3191FEC051F9F115E88F0A3E8AFAE96BA0DFB4DFEF'
$expectedInitrd = '3B451F2098AE2E3CCF76B618BA742184D795393C25D6B229130AB106BC33FFA5'

function Get-Sha256([string] $Path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }
function Test-PeArm64([string] $Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = [IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { return $false }
        $stream.Position = 0x3C; $offset = $reader.ReadUInt32()
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550) { return $false }
        return ($reader.ReadUInt16() -eq 0xAA64)
    }
    finally { $stream.Dispose() }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script in an elevated PowerShell window.' }
if (-not (Test-Path -LiteralPath $CandidateRaw)) { throw "Missing raw candidate: $CandidateRaw" }
if (-not (Test-Path -LiteralPath $VhdPath)) { throw "Missing retained VHD: $VhdPath" }
if ((Get-Item -LiteralPath $CandidateRaw).Length -ne $expectedBytes) { throw 'Raw candidate length mismatch.' }
if (Test-Path -LiteralPath $ReportPath) { throw "Refusing to overwrite report: $ReportPath" }

$reportDirectory = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
$attached = $false
try {
    Mount-DiskImage -ImagePath $VhdPath | Out-Null
    $attached = $true
    $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
    if ($disk.Size -ne $expectedBytes) { throw 'VHD virtual size mismatch.' }
    $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq $expectedOffset -and $_.Size -eq $expectedPartitionBytes }
    if (@($part).Count -ne 1) { throw 'Expected FAT32 geometry missing.' }
    $volume = $part | Get-Volume
    if ($volume.FileSystem -ne 'FAT32') { throw "Expected FAT32, got: $($volume.FileSystem)" }
    $letter = $volume.DriveLetter
    if (-not $letter) {
        Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AssignDriveLetter
        $letter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber | Get-Volume).DriveLetter
    }
    if (-not $letter) { throw 'No temporary VHD drive letter available.' }
    $root = "$letter`:"
    $grub = Join-Path $root 'EFI\BOOT\BOOTAA64.EFI'
    $cfg = Join-Path $root 'BOOT\GRUB\GRUB.CFG'
    $modulesCfg = Join-Path $root 'BOOT\GRUB\ARM64-EFI\GRUB.CFG'
    $linux = Join-Path $root 'DEBIAN-INSTALLER\ARM64\LINUX'
    $initrd = Join-Path $root 'DEBIAN-INSTALLER\ARM64\INITRD.GZ'
    $bcd = Join-Path $root 'EFI\Microsoft\Boot\BCD'
    $wim = Join-Path $root 'SOURCES\BOOT.WIM'
    foreach ($path in @($grub, $cfg, $modulesCfg, $linux, $initrd, $bcd, $wim)) { if (-not (Test-Path -LiteralPath $path)) { throw "Required control file missing: $path" } }
    if (-not (Test-PeArm64 $grub)) { throw 'BOOTAA64.EFI is not an ARM64 PE image.' }
    if ((Get-Sha256 $grub) -ne $expectedGrub) { throw 'GRUB hash mismatch.' }
    if ((Get-Sha256 $linux) -ne $expectedLinux) { throw 'Linux kernel hash mismatch.' }
    if ((Get-Sha256 $initrd) -ne $expectedInitrd) { throw 'Initrd hash mismatch.' }
    $configText = Get-Content -LiteralPath $cfg -Raw
    foreach ($needle in @('acpi=force', 'console=ttyS0,115200n8', 'earlycon=uart8250,mmio32,0x3f8')) {
        if (-not $configText.Contains($needle)) { throw "GRUB config lacks required kernel argument: $needle" }
    }
    $chkdsk = (& "$env:SystemRoot\System32\chkdsk.exe" "$letter`:" 2>&1 | Out-String).TrimEnd()
    if ($LASTEXITCODE -ne 0) { throw "CHKDSK reported a filesystem error (exit $LASTEXITCODE)." }
    $lines = @(
        'RESULT=PASS',
        "RAW_PATH=$CandidateRaw",
        "RAW_BYTES=$((Get-Item -LiteralPath $CandidateRaw).Length)",
        "RAW_SHA256=$(Get-Sha256 $CandidateRaw)",
        "VHD_PATH=$VhdPath",
        "VHD_DISK_NUMBER=$($disk.Number)",
        "PARTITION_OFFSET=$($part.Offset)",
        "PARTITION_BYTES=$($part.Size)",
        "FILESYSTEM=$($volume.FileSystem)",
        'BOOTAA64_EFI_ARM64_PE=PASS',
        "BOOTAA64_EFI_SHA256=$expectedGrub",
        "LINUX_KERNEL_SHA256=$expectedLinux",
        "INITRD_SHA256=$expectedInitrd",
        'GRUB_ACPI_FORCE=PASS',
        'GRUB_SERIAL_CONSOLE=PASS',
        'CHKDSK=PASS',
        '', '--- CHKDSK ---', $chkdsk,
        '', 'NEXT=Candidate remains offline. Do not copy it to Android or launch a VM.'
    )
    [IO.File]::WriteAllText($ReportPath, ($lines -join [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Get-Content -LiteralPath $ReportPath
}
finally {
    if ($attached) { Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue }
}

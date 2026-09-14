[CmdletBinding()]
param(
    [string] $CandidateRaw = 'E:\winavf-linux-efi-stub-control-candidate.img',
    [string] $VhdPath = 'D:\winavf-linux-efi-stub-control-work-fixed.vhd',
    [string] $ExpectedLauncherSha256 = '4F40F842D5483071842F0C5847748BB161B89434F3F32611C62D254655B5F074',
    [string] $ExpectedEarlycon = 'earlycon=uart8250,mmio32,0x3f8',
    [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-efi-stub-control-20260911\offline-audit.txt'
)

# Elevated offline verifier for the direct EFI-stub candidate.  It only mounts
# the retained disposable VHD, performs normal read-only checks plus chkdsk,
# then detaches it.  It does not write Android storage or launch a VM.
$ErrorActionPreference = 'Stop'
$expectedBytes = [int64]9126805504
$expectedOffset = [int64]1048576
$expectedPartitionBytes = [int64]9125740032
$expectedLauncher = $ExpectedLauncherSha256.ToUpperInvariant()
$expectedLinux = '84B9C190BB4589C4A9527E3191FEC051F9F115E88F0A3E8AFAE96BA0DFB4DFEF'
$expectedInitrd = '3B451F2098AE2E3CCF76B618BA742184D795393C25D6B229130AB106BC33FFA5'
$expectedBcd = 'B90EF16B94C3DDA7D76CC39840BEFAA9786887517445C3B6F47EBC806D0AB105'
$expectedWim = 'A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4'

function Get-Sha256([string] $Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }
function Test-PeArm64([string] $Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = [IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) { return $false }
        $stream.Position = 0x3C; $offset = $reader.ReadUInt32(); $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550) { return $false }
        return ($reader.ReadUInt16() -eq 0xAA64)
    }
    finally { $stream.Dispose() }
}
function Test-UnicodeMarker([string] $Path, [string] $Marker) {
    ([Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($Path))).Contains($Marker)
}
function Test-AsciiMarker([string] $Path, [string] $Marker) {
    ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path))).Contains($Marker)
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent(); $principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script in an elevated PowerShell window.' }
foreach ($path in @($CandidateRaw, $VhdPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required candidate artifact: $path" } }
if ((Get-Item -LiteralPath $CandidateRaw).Length -ne $expectedBytes) { throw 'Raw candidate length mismatch.' }
if (Test-Path -LiteralPath $ReportPath) { throw "Refusing to overwrite report: $ReportPath" }

$reportDirectory = Split-Path -Parent $ReportPath; New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
$attached = $false
try {
    Mount-DiskImage -ImagePath $VhdPath | Out-Null; $attached = $true
    $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
    if ($disk.Size -ne $expectedBytes) { throw 'VHD virtual size mismatch.' }
    $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq $expectedOffset -and $_.Size -eq $expectedPartitionBytes }
    if (@($part).Count -ne 1) { throw 'Expected FAT32 geometry missing.' }
    $volume = $part | Get-Volume
    if ($volume.FileSystem -ne 'FAT32') { throw "Expected FAT32, got: $($volume.FileSystem)" }
    $letter = $volume.DriveLetter
    if (-not $letter) { Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AssignDriveLetter; $letter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber | Get-Volume).DriveLetter }
    if (-not $letter) { throw 'No temporary VHD drive letter available.' }
    $root = "$letter`:"; $launcher = Join-Path $root 'EFI\BOOT\BOOTAA64.EFI'; $linux = Join-Path $root 'DEBIAN-INSTALLER\ARM64\LINUX'; $initrd = Join-Path $root 'DEBIAN-INSTALLER\ARM64\INITRD.GZ'; $bcd = Join-Path $root 'EFI\Microsoft\Boot\BCD'; $wim = Join-Path $root 'SOURCES\BOOT.WIM'
    foreach ($path in @($launcher, $linux, $initrd, $bcd, $wim)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required candidate file missing: $path" } }
    if (-not (Test-PeArm64 $launcher)) { throw 'BOOTAA64.EFI is not an ARM64 PE image.' }
    if ((Get-Sha256 $launcher) -ne $expectedLauncher) { throw 'Direct launcher SHA-256 mismatch.' }
    if ((Get-Sha256 $linux) -ne $expectedLinux) { throw 'Linux Image SHA-256 mismatch.' }
    if ((Get-Sha256 $initrd) -ne $expectedInitrd) { throw 'Initrd SHA-256 mismatch.' }
    if ((Get-Sha256 $bcd) -ne $expectedBcd) { throw 'BCD changed unexpectedly.' }
    if ((Get-Sha256 $wim) -ne $expectedWim) { throw 'BOOT.WIM changed unexpectedly.' }
    foreach ($marker in @('L0', 'L1', 'L2', 'L3', 'LX')) { if (-not (Test-AsciiMarker $launcher $marker)) { throw "Launcher lacks expected raw marker: $marker" } }
    foreach ($marker in @('\DEBIAN-INSTALLER\ARM64\LINUX', $ExpectedEarlycon)) { if (-not (Test-UnicodeMarker $launcher $marker)) { throw "Launcher lacks expected embedded path/options: $marker" } }
    $chkdsk = (& "$env:SystemRoot\System32\chkdsk.exe" "$letter`:" 2>&1 | Out-String).TrimEnd()
    if ($LASTEXITCODE -ne 0) { throw "CHKDSK reported a filesystem error (exit $LASTEXITCODE)." }
    $lines = @('RESULT=PASS', "RAW_PATH=$CandidateRaw", "RAW_BYTES=$((Get-Item -LiteralPath $CandidateRaw).Length)", "RAW_SHA256=$(Get-Sha256 $CandidateRaw)", "VHD_PATH=$VhdPath", "VHD_DISK_NUMBER=$($disk.Number)", "PARTITION_OFFSET=$($part.Offset)", "PARTITION_BYTES=$($part.Size)", "FILESYSTEM=$($volume.FileSystem)", 'BOOTAA64_EFI_ARM64_PE=PASS', "BOOTAA64_EFI_SHA256=$expectedLauncher", 'DIRECT_EFI_STUB_MARKERS=PASS', "LINUX_IMAGE_SHA256=$expectedLinux", "INITRD_SHA256=$expectedInitrd", "BCD_SHA256_UNCHANGED=$expectedBcd", "BOOT_WIM_SHA256_UNCHANGED=$expectedWim", 'CHKDSK=PASS', '', '--- CHKDSK ---', $chkdsk, '', 'NEXT=Candidate remains offline. Do not copy it to Android or launch a VM.')
    [IO.File]::WriteAllText($ReportPath, ($lines -join [Environment]::NewLine), [Text.UTF8Encoding]::new($false)); Get-Content -LiteralPath $ReportPath
}
finally { if ($attached) { Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue } }

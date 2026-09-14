[CmdletBinding()]
param(
    [string] $BaselineRaw = 'E:\winavf-a3-append-only-runtime.img',
    [string] $AssetsRoot = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-acpi-control-20260911\netboot\debian-installer\arm64',
    [string] $LauncherEfi = 'C:\Users\denis\MainProjects\win11ontab\firmware-work\edk2\Build\ArmVirtKvmTool-AARCH64\DEBUG_GCC5\AARCH64\ArmPkg\Application\AvfLinuxEfiStubProbe\AvfLinuxEfiStubProbe\DEBUG\AvfLinuxEfiStubProbe.efi',
    [string] $ExpectedLauncherSha256 = '4F40F842D5483071842F0C5847748BB161B89434F3F32611C62D254655B5F074',
    [string] $VhdPath = 'D:\winavf-linux-efi-stub-control-work-fixed.vhd',
    [string] $OutputRaw = 'E:\winavf-linux-efi-stub-control-candidate.img',
    [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-efi-stub-control-20260911\materialize-report.txt'
)

# Elevated, disposable-only workflow.  It creates a fixed VHD from the exact
# immutable product baseline, then uses only the Windows FAT32 driver to:
#   (1) replace EFI\BOOT\BOOTAA64.EFI with the direct Linux EFI-stub launcher;
#   (2) add Debian's official ARM64 Image and initrd.
# It never formats/repartitions a disk, writes Android storage, changes BCD or
# boot.wim, changes firmware, or starts a VM.
$ErrorActionPreference = 'Stop'

$expectedBaseline = '2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7'
$expectedBytes = [int64]9126805504
$expectedOffset = [int64]1048576
$expectedPartitionBytes = [int64]9125740032
$expectedLauncher = $ExpectedLauncherSha256.ToUpperInvariant()
$expectedLinux = '84B9C190BB4589C4A9527E3191FEC051F9F115E88F0A3E8AFAE96BA0DFB4DFEF'
$expectedInitrd = '3B451F2098AE2E3CCF76B618BA742184D795393C25D6B229130AB106BC33FFA5'
$expectedBcd = 'B90EF16B94C3DDA7D76CC39840BEFAA9786887517445C3B6F47EBC806D0AB105'
$expectedWim = 'A0D1106F85ED9CF449182ED220BCC8480DDC645791D136D9C6AA4880177D48C4'

function Get-Sha256([string] $Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script in an elevated PowerShell window.' }

$baseline = (Resolve-Path -LiteralPath $BaselineRaw).Path
$assets = (Resolve-Path -LiteralPath $AssetsRoot).Path
$launcher = (Resolve-Path -LiteralPath $LauncherEfi).Path
$linux = Join-Path $assets 'linux'
$initrd = Join-Path $assets 'initrd.gz'
foreach ($path in @($linux, $initrd)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required Debian asset: $path" } }
if ((Get-Item -LiteralPath $baseline).Length -ne $expectedBytes) { throw 'Baseline raw length mismatch.' }
if ((Get-Sha256 $baseline) -ne $expectedBaseline) { throw 'Exact immutable baseline SHA-256 mismatch.' }
if ((Get-Sha256 $launcher) -ne $expectedLauncher) { throw 'Unexpected direct EFI-stub launcher SHA-256.' }
if ((Get-Sha256 $linux) -ne $expectedLinux) { throw 'Unexpected Debian ARM64 kernel SHA-256.' }
if ((Get-Sha256 $initrd) -ne $expectedInitrd) { throw 'Unexpected Debian ARM64 initrd SHA-256.' }
foreach ($path in @($VhdPath, $OutputRaw, $ReportPath)) { if (Test-Path -LiteralPath $path) { throw "Refusing to overwrite existing output: $path" } }

$reportDirectory = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
$diskpartFile = Join-Path $env:TEMP ('winavf-linux-efi-stub-' + [Guid]::NewGuid().ToString('N') + '.txt')
$vhdAttached = $false
try {
    $vhdMb = [int64]($expectedBytes / 1MB)
    @"
create vdisk file="$VhdPath" maximum=$vhdMb type=fixed
select vdisk file="$VhdPath"
attach vdisk
"@ | Set-Content -LiteralPath $diskpartFile -Encoding ascii
    & "$env:SystemRoot\System32\diskpart.exe" /s $diskpartFile
    if ($LASTEXITCODE -ne 0) { throw "DiskPart fixed-VHD creation failed: $LASTEXITCODE" }
    $vhdAttached = $true

    $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
    if ($disk.Size -ne $expectedBytes) { throw "Unexpected VHD disk size: $($disk.Size)" }
    $physical = "\\.\PhysicalDrive$($disk.Number)"

    # Explicitly read only from immutable raw; all writes target the new VHD.
    $input = [IO.File]::Open($baseline, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $output = [IO.File]::Open($physical, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try {
        $buffer = [byte[]]::new(8MB); [int64]$copied = 0
        while ($copied -lt $expectedBytes) {
            $want = [int][Math]::Min([int64]$buffer.Length, $expectedBytes - $copied)
            $read = $input.Read($buffer, 0, $want)
            if ($read -le 0) { throw 'Unexpected immutable baseline EOF.' }
            $output.Write($buffer, 0, $read); $copied += $read
        }
        $output.Flush($true)
    }
    finally { $output.Dispose(); $input.Dispose() }

    Update-Disk -Number $disk.Number
    $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq $expectedOffset -and $_.Size -eq $expectedPartitionBytes }
    if (@($part).Count -ne 1) { throw 'Expected FAT32 geometry not found in disposable VHD.' }
    $volume = $part | Get-Volume
    if ($volume.FileSystem -ne 'FAT32') { throw "Expected FAT32, got: $($volume.FileSystem)" }
    $letter = $volume.DriveLetter
    if (-not $letter) {
        Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AssignDriveLetter
        $letter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber | Get-Volume).DriveLetter
    }
    if (-not $letter) { throw 'Could not obtain a drive letter for disposable VHD.' }

    $root = "$letter`:"
    $bootaa = Join-Path $root 'EFI\BOOT\BOOTAA64.EFI'
    $bcd = Join-Path $root 'EFI\Microsoft\Boot\BCD'
    $wim = Join-Path $root 'SOURCES\BOOT.WIM'
    foreach ($path in @($bootaa, $bcd, $wim)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required baseline file missing: $path" } }
    if ((Get-Sha256 $bcd) -ne $expectedBcd) { throw 'Unexpected baseline BCD SHA-256.' }
    if ((Get-Sha256 $wim) -ne $expectedWim) { throw 'Unexpected baseline BOOT.WIM SHA-256.' }
    $originalBootaa = Get-Sha256 $bootaa

    $targetLinux = Join-Path $root 'DEBIAN-INSTALLER\ARM64'
    New-Item -ItemType Directory -Force -Path $targetLinux | Out-Null
    Copy-Item -LiteralPath $launcher -Destination $bootaa -Force
    Copy-Item -LiteralPath $linux -Destination (Join-Path $targetLinux 'LINUX') -Force
    Copy-Item -LiteralPath $initrd -Destination (Join-Path $targetLinux 'INITRD.GZ') -Force

    if ((Get-Sha256 $bootaa) -ne $expectedLauncher) { throw 'FAT read-back launcher hash mismatch.' }
    if ((Get-Sha256 $bcd) -ne $expectedBcd) { throw 'BCD changed unexpectedly.' }
    if ((Get-Sha256 $wim) -ne $expectedWim) { throw 'BOOT.WIM changed unexpectedly.' }
    if ((Get-Sha256 (Join-Path $targetLinux 'LINUX')) -ne $expectedLinux) { throw 'FAT read-back Linux Image hash mismatch.' }
    if ((Get-Sha256 (Join-Path $targetLinux 'INITRD.GZ')) -ne $expectedInitrd) { throw 'FAT read-back initrd hash mismatch.' }

    # A filesystem-level read-back can be satisfied from the Windows cache.
    # The runtime candidate, however, is copied from the block device.  Fully
    # detach and reattach the disposable VHD before that raw read so the FAT32
    # cache has committed its metadata and file contents to the VHD backing
    # file.  This is a transport flush boundary, not a filesystem mutation.
    Dismount-DiskImage -ImagePath $VhdPath
    $vhdAttached = $false
    Mount-DiskImage -ImagePath $VhdPath | Out-Null
    $vhdAttached = $true
    $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
    if ($disk.Size -ne $expectedBytes) { throw 'VHD size changed across flush/re-attach.' }
    $physical = "\\.\PhysicalDrive$($disk.Number)"
    $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq $expectedOffset -and $_.Size -eq $expectedPartitionBytes }
    if (@($part).Count -ne 1) { throw 'Expected FAT32 geometry changed across flush/re-attach.' }

    $rawIn = [IO.File]::Open($physical, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $rawOut = [IO.File]::Open($OutputRaw, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $buffer = [byte[]]::new(8MB); [int64]$copied = 0
        while ($copied -lt $expectedBytes) {
            $want = [int][Math]::Min([int64]$buffer.Length, $expectedBytes - $copied)
            $read = $rawIn.Read($buffer, 0, $want)
            if ($read -le 0) { throw 'Unexpected disposable VHD EOF.' }
            $rawOut.Write($buffer, 0, $read); $copied += $read
        }
        $rawOut.Flush($true)
    }
    finally { $rawOut.Dispose(); $rawIn.Dispose() }

    $lines = @(
        'RESULT=PASS', "BASELINE_RAW=$baseline", "BASELINE_SHA256=$expectedBaseline",
        "LAUNCHER_EFI=$launcher", "LAUNCHER_SHA256=$expectedLauncher",
        "DEBIAN_LINUX_SHA256=$expectedLinux", "DEBIAN_INITRD_SHA256=$expectedInitrd",
        "ORIGINAL_BOOTAA64_SHA256=$originalBootaa", "BCD_SHA256_UNCHANGED=$expectedBcd", "BOOT_WIM_SHA256_UNCHANGED=$expectedWim",
        "VHD_PATH=$VhdPath", 'FAT32_FLUSH_DETACH_REATTACH=PASS', "RAW_PATH=$OutputRaw", "RAW_BYTES=$((Get-Item -LiteralPath $OutputRaw).Length)",
        "RAW_SHA256=$(Get-Sha256 $OutputRaw)", "PARTITION_OFFSET=$($part.Offset)", "PARTITION_BYTES=$($part.Size)",
        'NEXT=Run offline audit only. Do not copy it to Android or launch a VM.'
    )
    [IO.File]::WriteAllText($ReportPath, ($lines -join [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Get-Content -LiteralPath $ReportPath
}
finally {
    if ($vhdAttached) { Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $diskpartFile -Force -ErrorAction SilentlyContinue
}

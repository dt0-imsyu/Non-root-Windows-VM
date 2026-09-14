[CmdletBinding()]
param(
    [string] $BaselineRaw = 'E:\winavf-a3-append-only-runtime.img',
    [string] $AssetsRoot = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-acpi-control-20260911\netboot\debian-installer\arm64',
    [string] $VhdPath = 'D:\winavf-linux-acpi-control-work-fixed.vhd',
    [string] $OutputRaw = 'E:\winavf-linux-acpi-control-bookworm-candidate.img',
    [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-acpi-control-20260911\materialize-report.txt'
)

# Elevated, disposable-only workflow. It copies the immutable raw baseline into
# a new fixed VHD and replaces the removable UEFI boot loader with Debian's
# ARM64 GRUB plus its standard kernel/initrd through the Windows FAT32 driver.
# It never formats, repartitions, writes Android storage, or launches a VM.
$ErrorActionPreference = 'Stop'

$expectedBaseline = '2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7'
$expectedBytes = [int64]9126805504
$expectedOffset = [int64]1048576
$expectedPartitionBytes = [int64]9125740032
$expectedGrub = '8E13D190B10BBDA24974DEE5D1B0BE4BA6207FB1FF19AA4465257A945A378B91'
$expectedLinux = '84B9C190BB4589C4A9527E3191FEC051F9F115E88F0A3E8AFAE96BA0DFB4DFEF'
$expectedInitrd = '3B451F2098AE2E3CCF76B618BA742184D795393C25D6B229130AB106BC33FFA5'

function Get-Sha256([string] $Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an elevated PowerShell window.'
}

$baseline = (Resolve-Path -LiteralPath $BaselineRaw).Path
$assets = (Resolve-Path -LiteralPath $AssetsRoot).Path
$config = Join-Path $PSScriptRoot 'grub.cfg'
$grub = Join-Path $assets 'grubaa64.efi'
$linux = Join-Path $assets 'linux'
$initrd = Join-Path $assets 'initrd.gz'
$modules = Join-Path $assets 'grub\arm64-efi'
foreach ($path in @($config, $grub, $linux, $initrd, $modules)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing required Linux control asset: $path" }
}
if ((Get-Item -LiteralPath $baseline).Length -ne $expectedBytes) { throw 'Baseline raw length mismatch.' }
if ((Get-Sha256 $baseline) -ne $expectedBaseline) { throw 'Exact immutable baseline SHA-256 mismatch.' }
if ((Get-Sha256 $grub) -ne $expectedGrub) { throw 'Unexpected Debian grubaa64.efi SHA-256.' }
if ((Get-Sha256 $linux) -ne $expectedLinux) { throw 'Unexpected Debian ARM64 kernel SHA-256.' }
if ((Get-Sha256 $initrd) -ne $expectedInitrd) { throw 'Unexpected Debian ARM64 initrd SHA-256.' }
if (Test-Path -LiteralPath $VhdPath) { throw "Refusing to overwrite retained VHD: $VhdPath" }
if (Test-Path -LiteralPath $OutputRaw) { throw "Refusing to overwrite candidate raw image: $OutputRaw" }
if (Test-Path -LiteralPath $ReportPath) { throw "Refusing to overwrite report: $ReportPath" }

$reportDirectory = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
$diskpartFile = Join-Path $env:TEMP ('winavf-linux-acpi-' + [Guid]::NewGuid().ToString('N') + '.txt')
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

    # Source is immutable read-only raw; destination is the newly-created VHD.
    $input = [IO.File]::Open($baseline, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $output = [IO.File]::Open($physical, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try {
        $buffer = [byte[]]::new(8MB); [int64]$copied = 0
        while ($copied -lt $expectedBytes) {
            $want = [int][Math]::Min([int64]$buffer.Length, $expectedBytes - $copied)
            $read = $input.Read($buffer, 0, $want)
            if ($read -le 0) { throw 'Unexpected baseline EOF while populating disposable VHD.' }
            $output.Write($buffer, 0, $read); $copied += $read
        }
        $output.Flush($true)
    }
    finally { $output.Dispose(); $input.Dispose() }

    Update-Disk -Number $disk.Number
    $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq $expectedOffset -and $_.Size -eq $expectedPartitionBytes }
    if (@($part).Count -ne 1) { throw 'Expected baseline FAT32 geometry not found in disposable VHD.' }
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
    foreach ($path in @($bootaa, $bcd, $wim)) { if (-not (Test-Path -LiteralPath $path)) { throw "Required baseline file missing: $path" } }
    $bcdBefore = Get-Sha256 $bcd
    $wimBefore = Get-Sha256 $wim
    $bootaaBefore = Get-Sha256 $bootaa

    $targetGrub = Join-Path $root 'BOOT\GRUB'
    $targetModules = Join-Path $targetGrub 'ARM64-EFI'
    $targetLinux = Join-Path $root 'DEBIAN-INSTALLER\ARM64'
    New-Item -ItemType Directory -Force -Path $targetModules, $targetLinux | Out-Null
    Copy-Item -LiteralPath $grub -Destination $bootaa -Force
    Copy-Item -LiteralPath $config -Destination (Join-Path $targetGrub 'GRUB.CFG') -Force
    Copy-Item -Path (Join-Path $modules '*') -Destination $targetModules -Recurse -Force
    Copy-Item -LiteralPath $linux -Destination (Join-Path $targetLinux 'LINUX') -Force
    Copy-Item -LiteralPath $initrd -Destination (Join-Path $targetLinux 'INITRD.GZ') -Force

    if ((Get-Sha256 $bootaa) -ne $expectedGrub) { throw 'FAT read-back grubaa64.efi hash mismatch.' }
    if ((Get-Sha256 $bcd) -ne $bcdBefore) { throw 'BCD changed unexpectedly.' }
    if ((Get-Sha256 $wim) -ne $wimBefore) { throw 'BOOT.WIM changed unexpectedly.' }
    if ((Get-Sha256 (Join-Path $targetLinux 'LINUX')) -ne $expectedLinux) { throw 'FAT read-back Linux kernel hash mismatch.' }
    if ((Get-Sha256 (Join-Path $targetLinux 'INITRD.GZ')) -ne $expectedInitrd) { throw 'FAT read-back initrd hash mismatch.' }

    # Produce the raw candidate only after all semantic writes were read back.
    $rawIn = [IO.File]::Open($physical, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $rawOut = [IO.File]::Open($OutputRaw, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $buffer = [byte[]]::new(8MB); [int64]$copied = 0
        while ($copied -lt $expectedBytes) {
            $want = [int][Math]::Min([int64]$buffer.Length, $expectedBytes - $copied)
            $read = $rawIn.Read($buffer, 0, $want)
            if ($read -le 0) { throw 'Unexpected disposable VHD EOF while writing raw candidate.' }
            $rawOut.Write($buffer, 0, $read); $copied += $read
        }
        $rawOut.Flush($true)
    }
    finally { $rawOut.Dispose(); $rawIn.Dispose() }

    $lines = @(
        'RESULT=PASS',
        "BASELINE_RAW=$baseline",
        "BASELINE_SHA256=$expectedBaseline",
        "DEBIAN_GRUB_SHA256=$expectedGrub",
        "DEBIAN_LINUX_SHA256=$expectedLinux",
        "DEBIAN_INITRD_SHA256=$expectedInitrd",
        "ORIGINAL_BOOTAA64_SHA256=$bootaaBefore",
        "BCD_SHA256_UNCHANGED=$bcdBefore",
        "BOOT_WIM_SHA256_UNCHANGED=$wimBefore",
        "VHD_PATH=$VhdPath",
        "RAW_PATH=$OutputRaw",
        "RAW_BYTES=$((Get-Item -LiteralPath $OutputRaw).Length)",
        "RAW_SHA256=$(Get-Sha256 $OutputRaw)",
        "PARTITION_OFFSET=$($part.Offset)",
        "PARTITION_BYTES=$($part.Size)",
        'NEXT=Run offline audit only. Do not copy to Android or launch a VM.'
    )
    [IO.File]::WriteAllText($ReportPath, ($lines -join [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Get-Content -LiteralPath $ReportPath
}
finally {
    if ($vhdAttached) { Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $diskpartFile -Force -ErrorAction SilentlyContinue
}

[CmdletBinding()]
param(
    [string] $BaselineRaw = 'E:\winavf-a3-append-only-runtime.img',
    [string] $IsoPath = '',
    [string] $VhdPath = 'D:\winavf-ltsc-setup-26100.1742-work-fixed.vhd',
    [string] $OutputRaw = 'E:\winavf-ltsc-setup-26100.1742-candidate.img',
    [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\ltsc-setup-ab-20260910\materialize-report.txt'
)

# Requires an elevated PowerShell.  This is deliberately a Windows-storage-only
# workflow: it creates a disposable fixed VHD, copies the immutable raw baseline
# into it, then replaces only \SOURCES\BOOT.WIM through the normal FAT driver.
# It does not format, partition, touch the Android image, or launch a VM.
$ErrorActionPreference = 'Stop'

$expectedBaseline = '2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7'
$expectedIsoWim = '375DF1744A6D49836D91181D4C85450D9EEB15F8BF8C06AC25622FD5F0DD467B'
$expectedOffset = [int64]1048576
$expectedPartitionBytes = [int64]9125740032

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an elevated PowerShell window.'
}

$baseline = (Resolve-Path -LiteralPath $BaselineRaw).Path
if ([string]::IsNullOrWhiteSpace($IsoPath)) {
    # Do not embed a localized Downloads path: Windows PowerShell 5.1 may read a
    # UTF-8 script as an ANSI file.  The official ISO filename is ASCII and unique.
    $isoFileName = '26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_IOT_LTSC_EVAL_A64FRE_en-us.iso'
    $isoMatch = foreach ($directory in (Get-ChildItem -LiteralPath 'E:\' -Directory -ErrorAction Stop)) {
        $candidate = Join-Path $directory.FullName $isoFileName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { Get-Item -LiteralPath $candidate }
    }
    if (@($isoMatch).Count -ne 1) { throw 'Expected exactly one LTSC ISO under E:\. Pass -IsoPath explicitly if necessary.' }
    $IsoPath = $isoMatch.FullName
}
$iso = (Resolve-Path -LiteralPath $IsoPath).Path
if (Test-Path -LiteralPath $VhdPath) { throw "Refusing to overwrite retained VHD: $VhdPath" }
if (Test-Path -LiteralPath $OutputRaw) { throw "Refusing to overwrite raw candidate: $OutputRaw" }

$reportDir = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$baselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $baseline).Hash
if ($baselineHash -ne $expectedBaseline) { throw "Baseline SHA-256 mismatch: $baselineHash" }

$bytes = (Get-Item -LiteralPath $baseline).Length
if ($bytes % 1MB -ne 0) { throw 'Baseline length must be an exact MiB count for a fixed VHD.' }

$isoWasAttached = (Get-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue).Attached
$isoAttachedByScript = $false
$vhdAttached = $false
$diskpartFile = Join-Path $env:TEMP ('winavf-ltsc-vhd-' + [Guid]::NewGuid().ToString('N') + '.txt')

try {
    if (-not $isoWasAttached) {
        Mount-DiskImage -ImagePath $iso -Access ReadOnly | Out-Null
        $isoAttachedByScript = $true
    }
    $isoVolume = Get-DiskImage -ImagePath $iso | Get-Volume | Where-Object { $_.DriveLetter } | Select-Object -First 1
    if (-not $isoVolume) { throw 'Could not obtain a drive letter for the mounted ISO.' }
    $sourceWim = "$($isoVolume.DriveLetter):\sources\boot.wim"
    if (-not (Test-Path -LiteralPath $sourceWim)) { throw "LTSC ISO lacks sources\\boot.wim: $sourceWim" }
    $sourceWimHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceWim).Hash
    if ($sourceWimHash -ne $expectedIsoWim) { throw "Unexpected LTSC boot.wim SHA-256: $sourceWimHash" }

    $vhdMb = [int64]($bytes / 1MB)
    @"
create vdisk file="$VhdPath" maximum=$vhdMb type=fixed
select vdisk file="$VhdPath"
attach vdisk
"@ | Set-Content -LiteralPath $diskpartFile -Encoding ascii
    & "$env:SystemRoot\System32\diskpart.exe" /s $diskpartFile
    if ($LASTEXITCODE -ne 0) { throw "DiskPart fixed-VHD creation failed: $LASTEXITCODE" }
    $vhdAttached = $true

    $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
    if ($disk.Size -ne $bytes) { throw "Unexpected VHD size: $($disk.Size) != $bytes" }
    $physical = "\\.\PhysicalDrive$($disk.Number)"

    # Write only to the newly-created temporary VHD, never to the source image.
    $input = [IO.File]::Open($baseline, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $output = [IO.File]::Open($physical, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try {
        $buffer = [byte[]]::new(8MB); [int64]$copied = 0
        while ($copied -lt $bytes) {
            $want = [int][Math]::Min([int64]$buffer.Length, $bytes - $copied)
            $read = $input.Read($buffer, 0, $want)
            if ($read -le 0) { throw 'Unexpected baseline EOF while populating the temporary VHD.' }
            $output.Write($buffer, 0, $read); $copied += $read
        }
        $output.Flush($true)
    } finally { $output.Dispose(); $input.Dispose() }

    Update-Disk -Number $disk.Number
    $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq $expectedOffset -and $_.Size -eq $expectedPartitionBytes }
    if (@($part).Count -ne 1) { throw 'Expected FAT32 partition geometry was not found in temporary VHD.' }
    $volume = $part | Get-Volume
    if ($volume.FileSystem -ne 'FAT32') { throw "Expected FAT32, found: $($volume.FileSystem)" }
    $letter = $volume.DriveLetter
    if (-not $letter) {
        Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AssignDriveLetter
        $letter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber | Get-Volume).DriveLetter
    }
    if (-not $letter) { throw 'Could not obtain a drive letter for temporary VHD.' }

    $targetWim = "$letter`:\SOURCES\BOOT.WIM"
    $bootaa64 = "$letter`:\EFI\BOOT\BOOTAA64.EFI"
    $bcd = "$letter`:\EFI\Microsoft\Boot\BCD"
    foreach ($path in @($targetWim, $bootaa64, $bcd)) { if (-not (Test-Path -LiteralPath $path)) { throw "Required baseline file missing: $path" } }

    $wimBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetWim).Hash
    $bootaa64Before = (Get-FileHash -Algorithm SHA256 -LiteralPath $bootaa64).Hash
    $bcdBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $bcd).Hash

    # This is an ordinary replace operation on the mounted FAT32 filesystem.
    Copy-Item -LiteralPath $sourceWim -Destination $targetWim -Force
    $wimAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetWim).Hash
    if ($wimAfter -ne $expectedIsoWim) { throw "FAT read-back WIM SHA-256 mismatch: $wimAfter" }
    $bootaa64After = (Get-FileHash -Algorithm SHA256 -LiteralPath $bootaa64).Hash
    $bcdAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $bcd).Hash
    if ($bootaa64After -ne $bootaa64Before) { throw 'BOOTAA64.EFI changed unexpectedly.' }
    if ($bcdAfter -ne $bcdBefore) { throw 'BCD changed unexpectedly.' }

    # Sector-for-sector read from the temporary VHD through the Windows storage stack.
    $rawIn = [IO.File]::Open($physical, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $rawOut = [IO.File]::Open($OutputRaw, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $buffer = [byte[]]::new(8MB); [int64]$copied = 0
        while ($copied -lt $bytes) {
            $want = [int][Math]::Min([int64]$buffer.Length, $bytes - $copied)
            $read = $rawIn.Read($buffer, 0, $want)
            if ($read -le 0) { throw 'Unexpected temporary VHD EOF while writing raw candidate.' }
            $rawOut.Write($buffer, 0, $read); $copied += $read
        }
        $rawOut.Flush($true)
    } finally { $rawOut.Dispose(); $rawIn.Dispose() }

    $candidateHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputRaw).Hash
    $result = [ordered]@{
        Result = 'PASS'
        BaselineRaw = $baseline
        BaselineSha256 = $baselineHash
        SourceIso = $iso
        SourceIsoBootWimSha256 = $sourceWimHash
        PreviousBootWimSha256 = $wimBefore
        NewBootWimSha256 = $wimAfter
        BootWimBytes = (Get-Item -LiteralPath $targetWim).Length
        BootAa64BeforeAfter = "$bootaa64Before / $bootaa64After"
        BcdBeforeAfter = "$bcdBefore / $bcdAfter"
        VhdRetainedDetached = $VhdPath
        CandidateRaw = $OutputRaw
        CandidateBytes = (Get-Item -LiteralPath $OutputRaw).Length
        CandidateSha256 = $candidateHash
        PartitionOffset = $part.Offset
        PartitionBytes = $part.Size
        Next = 'Run offline audit only. Do not copy to Android or launch a VM.'
    }
    $resultLines = foreach ($entry in $result.GetEnumerator()) { "$($entry.Key)=$($entry.Value)" }
    [IO.File]::WriteAllText($ReportPath, ($resultLines -join [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Get-Content -LiteralPath $ReportPath
}
finally {
    if ($vhdAttached) { Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue }
    if ($isoAttachedByScript) { Dismount-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $diskpartFile -Force -ErrorAction SilentlyContinue
}

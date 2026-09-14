[CmdletBinding()]
param(
    [string] $CandidateRaw = 'E:\winavf-ltsc-setup-26100.1742-candidate.img',
    [string] $VhdPath = 'D:\winavf-ltsc-setup-26100.1742-work-fixed.vhd',
    [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\ltsc-setup-ab-20260910\offline-audit.txt'
)

# Elevated offline audit only.  No Android operation, VM launch, partitioning,
# formatting, or custom FAT manipulation is performed.
$ErrorActionPreference = 'Stop'
$expectedWim = '375DF1744A6D49836D91181D4C85450D9EEB15F8BF8C06AC25622FD5F0DD467B'
$expectedBytes = [int64]9126805504
$expectedOffset = [int64]1048576
$expectedPartitionBytes = [int64]9125740032
$wimlib = 'C:\Users\denis\MainProjects\win11ontab\tools\wimlib-1.14.5\wimlib-imagex.exe'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script in an elevated PowerShell window.' }
if (-not (Test-Path -LiteralPath $CandidateRaw)) { throw "Missing raw candidate: $CandidateRaw" }
if (-not (Test-Path -LiteralPath $VhdPath)) { throw "Missing retained VHD: $VhdPath" }
if (-not (Test-Path -LiteralPath $wimlib)) { throw "Missing wimlib-imagex: $wimlib" }
if ((Get-Item -LiteralPath $CandidateRaw).Length -ne $expectedBytes) { throw 'Raw candidate length mismatch.' }

$reportDir = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
if (Test-Path -LiteralPath $ReportPath) { throw "Refusing to overwrite audit report: $ReportPath" }

$attached = $false
try {
    Mount-DiskImage -ImagePath $VhdPath | Out-Null
    $attached = $true
    $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
    if ($disk.Size -ne $expectedBytes) { throw "VHD virtual size mismatch: $($disk.Size)" }
    $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq $expectedOffset -and $_.Size -eq $expectedPartitionBytes }
    if (@($part).Count -ne 1) { throw 'Expected FAT32 partition geometry missing.' }
    $volume = $part | Get-Volume
    if ($volume.FileSystem -ne 'FAT32') { throw "Expected FAT32, got: $($volume.FileSystem)" }
    $letter = $volume.DriveLetter
    if (-not $letter) {
        Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AssignDriveLetter
        $letter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber | Get-Volume).DriveLetter
    }
    if (-not $letter) { throw 'No temporary VHD drive letter available.' }

    $wim = "$letter`:\SOURCES\BOOT.WIM"
    $bootaa64 = "$letter`:\EFI\BOOT\BOOTAA64.EFI"
    $bcd = "$letter`:\EFI\Microsoft\Boot\BCD"
    foreach ($path in @($wim, $bootaa64, $bcd)) { if (-not (Test-Path -LiteralPath $path)) { throw "Required file missing: $path" } }
    $wimHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $wim).Hash
    if ($wimHash -ne $expectedWim) { throw "BOOT.WIM SHA-256 mismatch: $wimHash" }

    $chkdsk = & "$env:SystemRoot\System32\chkdsk.exe" "$letter`:" /f 2>&1
    $chkdskExit = $LASTEXITCODE
    if ($chkdskExit -ne 0) { throw "CHKDSK did not report a clean FAT filesystem (exit $chkdskExit)." }
    $chkdskText = ($chkdsk | Out-String).TrimEnd()

    # wimlib writes progress/diagnostics to stderr even on success.  Capture it
    # without allowing PowerShell's strict native-stderr behavior to preempt the
    # actual exit-code check.
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $verify = (& $wimlib verify $wim 2>&1 | Out-String)
        $verifyExit = $LASTEXITCODE
        $index2 = (& $wimlib info $wim 2 2>&1 | Out-String)
        $index2Exit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $savedErrorActionPreference }
    if ($verifyExit -ne 0) { throw "wimlib verify failed (exit $verifyExit): $verify" }
    if ($index2Exit -ne 0) { throw "WIM index 2 is unreadable (exit $index2Exit): $index2" }

    $rawHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateRaw).Hash
    $lines = @(
        'RESULT=PASS',
        "RAW_PATH=$CandidateRaw",
        "RAW_BYTES=$((Get-Item -LiteralPath $CandidateRaw).Length)",
        "RAW_SHA256=$rawHash",
        "VHD_PATH=$VhdPath",
        "VHD_DISK_NUMBER=$($disk.Number)",
        "PARTITION_OFFSET=$($part.Offset)",
        "PARTITION_BYTES=$($part.Size)",
        "FILESYSTEM=$($volume.FileSystem)",
        "BOOT_WIM_SHA256=$wimHash",
        "BOOTAA64_EFI_SHA256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $bootaa64).Hash)",
        "BCD_SHA256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $bcd).Hash)",
        'CHKDSK=PASS',
        'WIMLIB_VERIFY=PASS',
        'WIM_INDEX_2_READABLE=PASS',
        '', '--- CHKDSK ---', $chkdskText,
        '', '--- WIM INDEX 2 ---', $index2,
        '', 'NEXT=Candidate remains offline. Do not copy it to Android or launch a VM.'
    )
    [IO.File]::WriteAllText($ReportPath, ($lines -join [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Get-Content -LiteralPath $ReportPath
}
finally {
    if ($attached) { Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue }
}

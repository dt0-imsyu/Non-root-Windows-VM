param(
    [Parameter(Mandatory = $true)] [string] $SourceRaw,
    [Parameter(Mandatory = $true)] [string] $SourceSha256,
    [Parameter(Mandatory = $true)] [string] $BcdCandidate,
    [Parameter(Mandatory = $true)] [string] $BcdSha256,
    [Parameter(Mandatory = $true)] [string] $VhdPath,
    [Parameter(Mandatory = $true)] [string] $OutputRaw,
    [Parameter(Mandatory = $true)] [string] $ReportPath
)

# Elevated, disposable Windows-storage workflow. No custom FAT parsing/writing.
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourceRaw).Path
$bcd = (Resolve-Path -LiteralPath $BcdCandidate).Path
if (Test-Path -LiteralPath $VhdPath) { throw "Refusing to overwrite VHD: $VhdPath" }
if (Test-Path -LiteralPath $OutputRaw) { throw "Refusing to overwrite raw candidate: $OutputRaw" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne $SourceSha256.ToUpperInvariant()) { throw 'Source hash mismatch.' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $bcd).Hash -ne $BcdSha256.ToUpperInvariant()) { throw 'BCD candidate hash mismatch.' }

$bytes = (Get-Item -LiteralPath $source).Length
if ($bytes % 1MB -ne 0) { throw 'Source size must be an exact MiB count for diskpart fixed VHD.' }
$vhdMb = [int64]($bytes / 1MB)
$dp = Join-Path $env:TEMP ('winavf-kd-vhd-' + [Guid]::NewGuid().ToString('N') + '.txt')
@"
create vdisk file="$VhdPath" maximum=$vhdMb type=fixed
select vdisk file="$VhdPath"
attach vdisk
"@ | Set-Content -LiteralPath $dp -Encoding ascii

$attached = $false
try {
    & "$env:SystemRoot\System32\diskpart.exe" /s $dp
    if ($LASTEXITCODE -ne 0) { throw "diskpart create/attach failed: $LASTEXITCODE" }
    $attached = $true
    $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
    if ($disk.Size -ne $bytes) { throw "VHD virtual size mismatch: $($disk.Size) != $bytes" }
    $physical = "\\.\PhysicalDrive$($disk.Number)"

    $input = [IO.File]::Open($source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $output = [IO.File]::Open($physical, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try {
        $buffer = [byte[]]::new(8MB); [int64]$copied = 0
        while ($copied -lt $bytes) {
            $want = [int][Math]::Min([int64]$buffer.Length, $bytes - $copied)
            $read = $input.Read($buffer, 0, $want)
            if ($read -le 0) { throw 'Unexpected source EOF.' }
            $output.Write($buffer, 0, $read); $copied += $read
        }
        $output.Flush($true)
    } finally { $output.Dispose(); $input.Dispose() }

    Get-Disk -Number $disk.Number | Update-Disk
    $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq 1048576 -and $_.Size -eq 9125740032 }
    if (@($part).Count -ne 1) { throw 'Expected FAT32 partition was not found in temporary VHD.' }
    Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AssignDriveLetter
    $letter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber | Get-Volume).DriveLetter
    if (-not $letter) { throw 'Could not assign a drive letter to temporary VHD partition.' }
    $targetBcd = "$letter`:\EFI\Microsoft\Boot\BCD"
    if (-not (Test-Path -LiteralPath $targetBcd)) { throw "BCD missing in VHD: $targetBcd" }
    Copy-Item -LiteralPath $bcd -Destination $targetBcd -Force
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $targetBcd).Hash -ne $BcdSha256.ToUpperInvariant()) { throw 'Windows FAT copy read-back hash mismatch.' }

    $rawIn = [IO.File]::Open($physical, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $rawOut = [IO.File]::Open($OutputRaw, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $buffer = [byte[]]::new(8MB); [int64]$copied = 0
        while ($copied -lt $bytes) {
            $want = [int][Math]::Min([int64]$buffer.Length, $bytes - $copied)
            $read = $rawIn.Read($buffer, 0, $want)
            if ($read -le 0) { throw 'Unexpected VHD physical EOF.' }
            $rawOut.Write($buffer, 0, $read); $copied += $read
        }
        $rawOut.Flush($true)
    } finally { $rawOut.Dispose(); $rawIn.Dispose() }

    [pscustomobject]@{ Vhd=$VhdPath; PhysicalDrive=$physical; DiskNumber=$disk.Number; VirtualBytes=$bytes; DriveLetter=$letter; BcdSha256=$BcdSha256; OutputRaw=$OutputRaw; OutputBytes=(Get-Item -LiteralPath $OutputRaw).Length } | Format-List | Set-Content -LiteralPath $ReportPath -Encoding UTF8
} finally {
    if ($attached) { Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $dp -Force -ErrorAction SilentlyContinue
}

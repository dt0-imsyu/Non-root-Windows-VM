<#
Builds a WAVFPAT1 delta from two same-sized raw files without interpreting or
altering GPT/FAT/Windows contents.  Each changed block embeds old and new bytes
and the script proves, through an in-memory overlay, that application to the
verified baseline reconstructs the candidate SHA-256 exactly.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string] $BaselinePath,
  [Parameter(Mandatory=$true)][string] $CandidatePath,
  [Parameter(Mandatory=$true)][string] $ExpectedBaselineSha256,
  [Parameter(Mandatory=$true)][string] $ExpectedCandidateSha256,
  [Parameter(Mandatory=$true)][string] $PatchPath,
  [Parameter(Mandatory=$true)][string] $ReportPath,
  [int] $BlockBytes = 4194304
)
$ErrorActionPreference = 'Stop'
if ($BlockBytes -lt 4096 -or $BlockBytes -gt 67108864 -or ($BlockBytes % 4096) -ne 0) { throw 'BlockBytes must be 4 KiB-aligned and 4 KiB..64 MiB.' }
$baseline = (Resolve-Path -LiteralPath $BaselinePath).Path
$candidate = (Resolve-Path -LiteralPath $CandidatePath).Path
if (Test-Path -LiteralPath $PatchPath) { throw "Refusing to overwrite patch: $PatchPath" }
if ((Get-Item -LiteralPath $baseline).Length -ne (Get-Item -LiteralPath $candidate).Length) { throw 'Raw image lengths differ.' }
$baseHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $baseline).Hash.ToUpperInvariant()
$candidateHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidate).Hash.ToUpperInvariant()
if ($baseHash -ne $ExpectedBaselineSha256.ToUpperInvariant()) { throw "Baseline SHA-256 mismatch: $baseHash" }
if ($candidateHash -ne $ExpectedCandidateSha256.ToUpperInvariant()) { throw "Candidate SHA-256 mismatch: $candidateHash" }

function Read-Exact([IO.Stream] $stream, [byte[]] $buffer) { $offset=0; while($offset -lt $buffer.Length){$n=$stream.Read($buffer,$offset,$buffer.Length-$offset);if($n -le 0){throw 'Unexpected EOF.'};$offset += $n} }
function Hash([byte[]] $bytes) { [Security.Cryptography.SHA256]::HashData($bytes) }
function Write-Bytes([IO.Stream] $stream, [byte[]] $bytes) { $stream.Write($bytes,0,$bytes.Length) }
function Hex-ToBytes([string] $hex) {
  if (($hex.Length % 2) -ne 0) { throw 'Hex string has an odd length.' }
  $bytes = New-Object byte[] ($hex.Length / 2)
  for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
  return ,$bytes
}
function Bytes-ToHex([byte[]] $bytes) { return ([BitConverter]::ToString($bytes).Replace('-', '')) }

$ranges = [Collections.Generic.List[object]]::new()
$left = [IO.File]::OpenRead($baseline); $right = [IO.File]::OpenRead($candidate)
try {
  [int64] $offset=0
  while($offset -lt $left.Length) {
    [int] $take=[int][Math]::Min([int64]$BlockBytes,$left.Length-$offset)
    $old=New-Object byte[] $take; $new=New-Object byte[] $take
    Read-Exact $left $old; Read-Exact $right $new
    if(-not [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($old,$new)) { $ranges.Add([pscustomobject]@{Offset=$offset;Old=$old;New=$new}) }
    $offset += $take
  }
} finally { $left.Dispose(); $right.Dispose() }
if($ranges.Count -eq 0){throw 'Candidate has no byte differences from baseline.'}

$parent=Split-Path -Parent $PatchPath; if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
$writer=[IO.BinaryWriter]::new([IO.File]::Open($PatchPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None),[Text.Encoding]::ASCII,$false)
try {
  Write-Bytes $writer.BaseStream ([Text.Encoding]::ASCII.GetBytes('WAVFPAT1')); $writer.Write([int32]1); $writer.Write([int64](Get-Item -LiteralPath $baseline).Length); Write-Bytes $writer.BaseStream (Hex-ToBytes $baseHash); $writer.Write([int32]$ranges.Count)
  foreach($range in $ranges){$writer.Write([int64]$range.Offset);$writer.Write([int32]$range.Old.Length);Write-Bytes $writer.BaseStream (Hash $range.Old);Write-Bytes $writer.BaseStream (Hash $range.New);Write-Bytes $writer.BaseStream $range.Old;Write-Bytes $writer.BaseStream $range.New}
  $writer.Flush();$writer.BaseStream.Flush($true)
} finally {$writer.Dispose()}

$sha=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
$source=[IO.File]::OpenRead($baseline)
try {
  [int64]$offset=0
  while($offset -lt $source.Length){[int]$take=[int][Math]::Min([int64]$BlockBytes,$source.Length-$offset);$buffer=New-Object byte[] $take;Read-Exact $source $buffer;foreach($range in $ranges){$start=[Math]::Max($offset,$range.Offset);$end=[Math]::Min($offset+$take,$range.Offset+$range.Old.Length);if($start-lt$end){[Array]::Copy($range.New,[int]($start-$range.Offset),$buffer,[int]($start-$offset),[int]($end-$start))}};$sha.AppendData($buffer);$offset += $take}
  $overlay = Bytes-ToHex ($sha.GetHashAndReset())
} finally {$source.Dispose();$sha.Dispose()}
if($overlay -ne $candidateHash){throw "Overlay reconstruction SHA-256 mismatch: $overlay"}

$report=@(
  'RESULT=PASS', "BASELINE_SHA256=$baseHash", "CANDIDATE_SHA256=$candidateHash", "PATCH_SHA256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $PatchPath).Hash)", "PATCH_BYTES=$((Get-Item -LiteralPath $PatchPath).Length)", "RANGES=$($ranges.Count)", "CHANGED_BLOCK_BYTES=$([int64](($ranges | ForEach-Object {$_.Old.Length}|Measure-Object -Sum).Sum))", "OVERLAY_RECONSTRUCTS_CANDIDATE=PASS"
)
$report | Set-Content -LiteralPath $ReportPath -Encoding ascii
$report

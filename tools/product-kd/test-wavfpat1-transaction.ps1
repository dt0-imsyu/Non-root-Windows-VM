<# Read-only transactional validator for a WAVFPAT1 bundle. #>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string] $BaselinePath,
  [Parameter(Mandatory=$true)][string] $CandidatePath,
  [Parameter(Mandatory=$true)][string] $PatchPath,
  [Parameter(Mandatory=$true)][string] $ExpectedCandidateSha256,
  [Parameter(Mandatory=$true)][string] $ReportPath,
  [int] $BlockBytes = 4194304
)
$ErrorActionPreference='Stop'
function Read-Exact([IO.BinaryReader]$reader,[int]$n){$b=$reader.ReadBytes($n);if($b.Length-ne$n){throw 'Truncated patch.'};return ,$b}
function Read-StreamExact([IO.Stream]$stream,[byte[]]$b){$o=0;while($o-lt$b.Length){$n=$stream.Read($b,$o,$b.Length-$o);if($n-le0){throw 'Unexpected EOF.'};$o+=$n}}
function Equal([byte[]]$a,[byte[]]$b){[Security.Cryptography.CryptographicOperations]::FixedTimeEquals($a,$b)}
function Bytes-ToHex([byte[]]$bytes){return ([BitConverter]::ToString($bytes).Replace('-', ''))}
$reader=[IO.BinaryReader]::new([IO.File]::OpenRead((Resolve-Path -LiteralPath $PatchPath)),[Text.Encoding]::ASCII,$false)
try {
  if([Text.Encoding]::ASCII.GetString((Read-Exact $reader 8)) -ne 'WAVFPAT1'){throw 'Patch magic mismatch.'}
  if($reader.ReadInt32()-ne1){throw 'Patch version mismatch.'}
  $length=$reader.ReadInt64();$baseHash=Read-Exact $reader 32;$count=$reader.ReadInt32();if($count-lt1){throw 'No patch ranges.'}
  $ranges=[Collections.Generic.List[object]]::new()
  for($i=0;$i-lt$count;$i++){$offset=$reader.ReadInt64();$n=$reader.ReadInt32();$oldHash=Read-Exact $reader 32;$newHash=Read-Exact $reader 32;$old=Read-Exact $reader $n;$new=Read-Exact $reader $n;if(-not(Equal ([Security.Cryptography.SHA256]::HashData($old)) $oldHash)){throw "Embedded old hash fails at $offset"};if(-not(Equal ([Security.Cryptography.SHA256]::HashData($new)) $newHash)){throw "Embedded new hash fails at $offset"};$ranges.Add([pscustomobject]@{Offset=$offset;Length=$n;Old=$old;New=$new;OldHash=$oldHash;NewHash=$newHash})}
  if($reader.BaseStream.Position-ne$reader.BaseStream.Length){throw 'Unexpected trailing patch bytes.'}
} finally {$reader.Dispose()}
$base=(Resolve-Path -LiteralPath $BaselinePath).Path;$candidate=(Resolve-Path -LiteralPath $CandidatePath).Path
if((Get-Item $base).Length-ne$length -or (Get-Item $candidate).Length-ne$length){throw 'Raw length differs from patch target.'}
$baseFull=(Get-FileHash -Algorithm SHA256 -LiteralPath $base).Hash.ToUpperInvariant();if($baseFull-ne(Bytes-ToHex $baseHash)){throw "Baseline full hash mismatch: $baseFull"}
$candidateFull=(Get-FileHash -Algorithm SHA256 -LiteralPath $candidate).Hash.ToUpperInvariant();if($candidateFull-ne$ExpectedCandidateSha256.ToUpperInvariant()){throw "Candidate full hash mismatch: $candidateFull"}
$left=[IO.File]::OpenRead($base);$right=[IO.File]::OpenRead($candidate)
try{foreach($range in $ranges){$old=New-Object byte[] $range.Length;$new=New-Object byte[] $range.Length;$left.Position=$range.Offset;$right.Position=$range.Offset;Read-StreamExact $left $old;Read-StreamExact $right $new;if(-not(Equal ([Security.Cryptography.SHA256]::HashData($old)) $range.OldHash)){throw "Baseline range mismatch at $($range.Offset)"};if(-not(Equal ([Security.Cryptography.SHA256]::HashData($new)) $range.NewHash)){throw "Candidate range mismatch at $($range.Offset)"}}}finally{$left.Dispose();$right.Dispose()}
$hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256);$stream=[IO.File]::OpenRead($candidate)
try{[int64]$offset=0;while($offset-lt$length){[int]$take=[int][Math]::Min([int64]$BlockBytes,$length-$offset);$b=New-Object byte[] $take;Read-StreamExact $stream $b;foreach($range in $ranges){$s=[Math]::Max($offset,$range.Offset);$e=[Math]::Min($offset+$take,$range.Offset+$range.Length);if($s-lt$e){[Array]::Copy($range.Old,[int]($s-$range.Offset),$b,[int]($s-$offset),[int]($e-$s))}};$hash.AppendData($b);$offset+=$take};$rollbackHash=Bytes-ToHex ($hash.GetHashAndReset())}finally{$stream.Dispose();$hash.Dispose()}
if($rollbackHash-ne$baseFull){throw "Rollback overlay mismatch: $rollbackHash"}
$result=@('RESULT=PASS',"BASELINE_SHA256=$baseFull", "CANDIDATE_SHA256=$candidateFull", "RANGES=$count", "ROLLBACK_OVERLAY_RESTORES_BASELINE=PASS")
$result|Set-Content -LiteralPath $ReportPath -Encoding ascii;$result

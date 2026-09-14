<#
Applies or rolls back the one r11 firmware range to the designated shell-only
BCD control clone. It refuses every other image and never accesses a disk.
#>
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Apply','Rollback')]
  [string] $Mode,
  [string] $RawPath = 'E:\winavf-kd-shell-clone-20260907-baseline.img',
  [string] $PatchPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\runtime-debug-uart-r11-20260908\runtime-r11-debug-uart-align-firmware.patch',
  [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\shell-windows-r11-bcd-control-20260908\local-firmware-range-transaction.txt'
)

$ErrorActionPreference = 'Stop'
$expectedPatchHash = '0D78B91BDA1B2C3EB241CF8B1D731280DB511958B3B196662046C76AF7E8364E'
$expectedRawPath = 'E:\winavf-kd-shell-clone-20260907-baseline.img'
function HashBytes([byte[]] $Bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)) }

$raw = (Resolve-Path -LiteralPath $RawPath).Path
$patch = (Resolve-Path -LiteralPath $PatchPath).Path
if ($raw -ne $expectedRawPath) { throw "Refusing a target other than the designated shell control clone: $raw" }
if ((Get-FileHash -LiteralPath $patch -Algorithm SHA256).Hash -ne $expectedPatchHash) { throw 'Unexpected r11 patch SHA-256.' }

$reader = [IO.BinaryReader]::new([IO.File]::OpenRead($patch))
try {
  if ([Text.Encoding]::ASCII.GetString($reader.ReadBytes(8)) -ne 'WAVFPAT1') { throw 'Unexpected patch magic.' }
  if ($reader.ReadInt32() -ne 1) { throw 'Unexpected patch version.' }
  $imageBytes = $reader.ReadInt64(); $baselineHash = [Convert]::ToHexString($reader.ReadBytes(32))
  if ($reader.ReadInt32() -ne 1) { throw 'Expected exactly one range.' }
  $offset = $reader.ReadInt64(); $length = $reader.ReadInt32()
  $oldHash = [Convert]::ToHexString($reader.ReadBytes(32)); $newHash = [Convert]::ToHexString($reader.ReadBytes(32))
  $oldBytes = $reader.ReadBytes($length); $newBytes = $reader.ReadBytes($length)
  if (($oldBytes.Length -ne $length) -or ($newBytes.Length -ne $length) -or ($reader.BaseStream.Position -ne $reader.BaseStream.Length)) { throw 'Patch range is truncated or has trailing bytes.' }
} finally { $reader.Dispose() }
if (((Get-Item -LiteralPath $raw).Length -ne $imageBytes) -or ($offset -ne 7250927616L) -or ($length -ne 2097152)) { throw 'Unexpected shell-control clone or firmware-range geometry.' }
if ((HashBytes $oldBytes) -ne $oldHash -or (HashBytes $newBytes) -ne $newHash) { throw 'Patch embedded range hashes do not validate.' }

$expectedBefore = if ($Mode -eq 'Apply') { $oldHash } else { $newHash }
$replacement = if ($Mode -eq 'Apply') { $newBytes } else { $oldBytes }
$expectedAfter = if ($Mode -eq 'Apply') { $newHash } else { $oldHash }
$stream = [IO.File]::Open($raw, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
try {
  $stream.Position = $offset; $before = [byte[]]::new($length); $read = 0
  while ($read -lt $length) { $n = $stream.Read($before, $read, $length - $read); if ($n -le 0) { throw 'Unexpected raw-image EOF.' }; $read += $n }
  if ((HashBytes $before) -ne $expectedBefore) { throw "Range precondition failed for $Mode." }
  $stream.Position = $offset; $stream.Write($replacement, 0, $replacement.Length); $stream.Flush($true)
  $stream.Position = $offset; $after = [byte[]]::new($length); $read = 0
  while ($read -lt $length) { $n = $stream.Read($after, $read, $length - $read); if ($n -le 0) { throw 'Unexpected raw-image EOF after write.' }; $read += $n }
  if ((HashBytes $after) -ne $expectedAfter) { throw "Range read-back failed for $Mode." }
} finally { $stream.Dispose() }
@("MODE=$Mode", "RAW=$raw", "PATCH_SHA256=$expectedPatchHash", "PATCH_BASELINE_SHA256=$baselineHash", "OFFSET=$offset", "LENGTH=$length", "BEFORE_SHA256=$expectedBefore", "AFTER_SHA256=$expectedAfter", 'RESULT=PASS') | Set-Content -LiteralPath $ReportPath -Encoding ascii
Get-Content -LiteralPath $ReportPath

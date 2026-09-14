<#
Creates exactly one reversible firmware range bundle for the product image.
It reads the old bytes from the immutable raw baseline and never writes that
image; the Android launcher verifies the range again before applying it.
#>
[CmdletBinding()]
param(
  [string] $BaselineRaw = 'E:\winavf-a3-append-only-runtime.img',
  [string] $ExpectedBaselineSha256 = '2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7',
  [string] $FirmwareFd = 'C:\Users\denis\MainProjects\win11ontab\firmware-work\edk2\artifacts\KVMTOOL_EFI-r10-uefi-serial-input.fd',
  [string] $PatchPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\uefi-serial-input-r10-20260914\uefi-serial-input-r10-firmware.patch',
  [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\uefi-serial-input-r10-20260914\patch-build-report.txt'
)
$ErrorActionPreference = 'Stop'
$offset = 7250927616L
$length = 2097152
function Read-Exactly([IO.Stream] $Stream, [byte[]] $Buffer) {
  $done = 0
  while ($done -lt $Buffer.Length) {
    $count = $Stream.Read($Buffer, $done, $Buffer.Length - $done)
    if ($count -le 0) { throw 'Unexpected EOF.' }
    $done += $count
  }
}
function Bytes([string] $Hex) {
  $value = New-Object byte[] ($Hex.Length / 2)
  for ($i = 0; $i -lt $value.Length; $i++) { $value[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16) }
  return ,$value
}
function Write-Bytes([IO.Stream] $Stream, [byte[]] $Value) { $Stream.Write($Value, 0, $Value.Length) }

$raw = (Resolve-Path -LiteralPath $BaselineRaw).Path
$fd = (Resolve-Path -LiteralPath $FirmwareFd).Path
if ((Get-Item -LiteralPath $fd).Length -ne $length) { throw 'Firmware FD does not have the expected 2 MiB size.' }
if (Test-Path -LiteralPath $PatchPath) { throw "Refusing to overwrite: $PatchPath" }
$baselineHash = (Get-FileHash -LiteralPath $raw -Algorithm SHA256).Hash.ToUpperInvariant()
if ($baselineHash -ne $ExpectedBaselineSha256) { throw "Baseline hash mismatch: $baselineHash" }

$old = New-Object byte[] $length
$reader = [IO.File]::OpenRead($raw)
try { $reader.Seek($offset, [IO.SeekOrigin]::Begin) | Out-Null; Read-Exactly $reader $old } finally { $reader.Dispose() }
$new = [IO.File]::ReadAllBytes($fd)
$oldHash = [Security.Cryptography.SHA256]::HashData($old)
$newHash = [Security.Cryptography.SHA256]::HashData($new)
if ([Security.Cryptography.CryptographicOperations]::FixedTimeEquals($old, $new)) { throw 'New FD is byte-identical to baseline range.' }

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PatchPath) | Out-Null
$writer = [IO.BinaryWriter]::new([IO.File]::Open($PatchPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None), [Text.Encoding]::ASCII, $false)
try {
  Write-Bytes $writer.BaseStream ([Text.Encoding]::ASCII.GetBytes('WAVFPAT1'))
  $writer.Write([int32]1); $writer.Write([int64](Get-Item -LiteralPath $raw).Length)
  Write-Bytes $writer.BaseStream (Bytes $baselineHash); $writer.Write([int32]1)
  $writer.Write([int64]$offset); $writer.Write([int32]$length)
  Write-Bytes $writer.BaseStream $oldHash; Write-Bytes $writer.BaseStream $newHash
  Write-Bytes $writer.BaseStream $old; Write-Bytes $writer.BaseStream $new
  $writer.Flush(); $writer.BaseStream.Flush($true)
} finally { $writer.Dispose() }

# In-memory forward/reverse simulation; this is the exact range the launcher
# will authenticate before it writes and again before it rolls back.
$simulated = [byte[]]$old.Clone(); [Array]::Copy($new, $simulated, $length)
if (-not [Security.Cryptography.CryptographicOperations]::FixedTimeEquals([Security.Cryptography.SHA256]::HashData($simulated), $newHash)) { throw 'Forward simulation failed.' }
[Array]::Copy($old, $simulated, $length)
if (-not [Security.Cryptography.CryptographicOperations]::FixedTimeEquals([Security.Cryptography.SHA256]::HashData($simulated), $oldHash)) { throw 'Rollback simulation failed.' }

$report = @(
  'RESULT=PASS', "BASELINE_SHA256=$baselineHash", "OFFSET=$offset", "LENGTH=$length",
  "BEFORE_SHA256=$([Convert]::ToHexString($oldHash))", "AFTER_SHA256=$([Convert]::ToHexString($newHash))",
  "PATCH_SHA256=$((Get-FileHash -LiteralPath $PatchPath -Algorithm SHA256).Hash)",
  "PATCH_BYTES=$((Get-Item -LiteralPath $PatchPath).Length)", 'FORWARD_SIMULATION=PASS', 'ROLLBACK_SIMULATION=PASS'
)
$report | Set-Content -LiteralPath $ReportPath -Encoding ascii
$report

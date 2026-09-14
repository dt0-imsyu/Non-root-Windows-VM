<#
Runs exactly one bounded app-owned Windows Setup witness experiment.

The app applies a separately validated static delta to an app-private clone,
then this runner stops that VM, requests a read-only FAT inspection of the
stopped clone, and asks the app to delete that clone.  The immutable external
baseline is never opened for write and is hashed both before and after.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string] $PatchPath,
  [Parameter(Mandatory = $true)][string] $ExpectedPatchSha256,
  [Parameter(Mandatory = $true)][string] $ArtifactDir,
  [string] $AdbPath = 'adb',
  [int] $DurationSeconds = 100,
  [string] $ProductImagePath = '/sdcard/Android/data/com.example.winavf/files/win11-gop-ebs-r1.img',
  [string] $ExpectedBaselineSha256 = '2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7'
)

$ErrorActionPreference = 'Stop'
if ($DurationSeconds -lt 30 -or $DurationSeconds -gt 180) { throw 'DurationSeconds must be 30..180.' }
$patch = (Resolve-Path -LiteralPath $PatchPath).Path
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash -ne $ExpectedPatchSha256.ToUpperInvariant()) { throw 'Local patch hash mismatch.' }
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
$artifact = (Resolve-Path -LiteralPath $ArtifactDir).Path
$status = Join-Path $artifact 'run-status.txt'
$remotePatch = '/sdcard/Android/data/com.example.winavf/files/winavf-image-patch.bin'
$app = 'com.example.winavf/.MainActivity'

function Invoke-Adb([string[]] $Arguments) { & $AdbPath @Arguments; if ($LASTEXITCODE -ne 0) { throw "adb failed ($LASTEXITCODE): $($Arguments -join ' ')" } }
function Remote-Hash([string] $Path) { $line = (& $AdbPath exec-out "sha256sum '$Path'" 2>$null) -join "`n"; if ($LASTEXITCODE -ne 0 -or $line -notmatch '^([0-9a-fA-F]{64})\s') { throw "Could not hash Android path: $Path" }; return $matches[1].ToUpperInvariant() }
function Read-Remote([string] $Path) { ((& $AdbPath shell cat $Path 2>$null) -join "`n") }

$previousPolicy = $null
try {
  $before = Remote-Hash $ProductImagePath
  if ($before -ne $ExpectedBaselineSha256.ToUpperInvariant()) { throw "Immutable baseline hash mismatch: $before" }
  Add-Content $status "BASELINE_BEFORE_SHA256=$before"
  Invoke-Adb @('push', $patch, $remotePatch)
  if ((Remote-Hash $remotePatch) -ne $ExpectedPatchSha256.ToUpperInvariant()) { throw 'Staged patch hash mismatch.' }
  $previousPolicy = ((& $AdbPath shell settings get global hidden_api_policy 2>$null) -join '').Trim()
  if ([string]::IsNullOrWhiteSpace($previousPolicy) -or $previousPolicy -eq 'null') { $previousPolicy = $null }
  Invoke-Adb @('shell','settings','put','global','hidden_api_policy','1')
  Invoke-Adb @('shell','am','force-stop','com.example.winavf')
  Invoke-Adb @('shell','rm','-f',
    '/sdcard/Android/data/com.example.winavf/files/persistent-boot-witness-report.txt',
    '/sdcard/Android/data/com.example.winavf/files/persistent-witness-setupact.log',
    '/sdcard/Android/data/com.example.winavf/files/persistent-witness-setuperr.log',
    '/sdcard/Android/data/com.example.winavf/files/persistent-witness-cleanup-report.txt',
    '/sdcard/Android/data/com.example.winavf/files/serial.log')
  Invoke-Adb @('shell','am','start','-n',$app,'--ez','start','true')
  Add-Content $status "ONE_VM_RUN_STARTED_UTC=$([DateTime]::UtcNow.ToString('O'))"
  Start-Sleep -Seconds $DurationSeconds
  Invoke-Adb @('shell','am','force-stop','com.example.winavf')
  Add-Content $status 'VM_STOPPED_BY_APP_FORCE_STOP=1'
  Start-Sleep -Seconds 3
  Invoke-Adb @('shell','am','start','-n',$app,'--ez','persistent_witness_audit','true')
  $deadline = [DateTime]::UtcNow.AddSeconds(45); $report = ''
  while ([DateTime]::UtcNow -lt $deadline) { $report = Read-Remote '/sdcard/Android/data/com.example.winavf/files/persistent-boot-witness-report.txt'; if ($report -match 'PERSISTENT_WINDOWS_SETUP_WITNESS=') { break }; Start-Sleep -Seconds 1 }
  $report | Set-Content -LiteralPath (Join-Path $artifact 'persistent-boot-witness-report.txt') -Encoding ascii
  foreach($name in @('persistent-witness-setupact.log','persistent-witness-setuperr.log','serial.log')) { & $AdbPath pull "/sdcard/Android/data/com.example.winavf/files/$name" (Join-Path $artifact $name) 2>$null | Out-Null }
  if ($report -notmatch 'PERSISTENT_WINDOWS_SETUP_WITNESS=') { throw 'Stopped-clone offline witness report was not produced.' }
} finally {
  try { Invoke-Adb @('shell','am','force-stop','com.example.winavf') } catch { }
  try {
    Invoke-Adb @('shell','am','start','-n',$app,'--ez','persistent_witness_cleanup','true')
    $deadline = [DateTime]::UtcNow.AddSeconds(45); $cleanup = ''
    while ([DateTime]::UtcNow -lt $deadline) { $cleanup = Read-Remote '/sdcard/Android/data/com.example.winavf/files/persistent-witness-cleanup-report.txt'; if ($cleanup -match 'RESULT=(PASS|FAIL)') { break }; Start-Sleep -Seconds 1 }
    $cleanup | Set-Content -LiteralPath (Join-Path $artifact 'cleanup-report.txt') -Encoding ascii
    if ($cleanup -notmatch 'RESULT=PASS' -or $cleanup -notmatch "IMMUTABLE_BASELINE_SHA256=$ExpectedBaselineSha256") { throw 'Disposable-clone cleanup did not verify immutable baseline.' }
    $after = Remote-Hash $ProductImagePath
    if ($after -ne $ExpectedBaselineSha256.ToUpperInvariant()) { throw "Immutable baseline hash mismatch after cleanup: $after" }
    Add-Content $status "BASELINE_AFTER_SHA256=$after"
  } finally {
    try { if ($null -eq $previousPolicy) { Invoke-Adb @('shell','settings','delete','global','hidden_api_policy') } else { Invoke-Adb @('shell','settings','put','global','hidden_api_policy',$previousPolicy) } } catch { }
    try { Invoke-Adb @('shell','rm','-f',$remotePatch) } catch { }
  }
}
Get-Content -LiteralPath $status

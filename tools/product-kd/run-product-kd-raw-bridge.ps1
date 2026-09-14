<#
One bounded diagnostic bridge for the app-owned product VM.

This script intentionally does not build, edit, or apply a Windows image
patch.  A separately audited WAVFPAT1 bundle must already be supplied.  The
Android launcher verifies the immutable product-baseline hash before it applies
that bundle and verifies it again when rollback is requested.

The transport is raw in both directions:
  kd.exe named pipe <-> adb-forwarded localhost TCP <-> getConsoleInput/Output
There is no PTY, base64, line protocol, or character conversion after the
short localhost capability-token handshake.
#>
[CmdletBinding()]
param(
  [string] $KdPath = 'C:\Program Files\WindowsApps\Microsoft.WinDbg_1.2606.22001.0_x64__8wekyb3d8bbwe\amd64\kd.exe',
  [Parameter(Mandatory = $true)][string] $PatchPath,
  [Parameter(Mandatory = $true)][string] $ExpectedPatchSha256,
  [Parameter(Mandatory = $true)][string] $ArtifactDir,
  [string] $AdbPath = 'adb',
  [int] $DurationSeconds = 100,
  [int] $GateTimeoutSeconds = 90,
  [string] $GateMarker = 'Loading files...',
  [string] $PipeName = ('winavf-product-kd-' + [Guid]::NewGuid().ToString('N')),
  [string] $ProductImagePath = '/sdcard/Android/data/com.example.winavf/files/win11-gop-ebs-r1.img',
  [string] $ExpectedBaselineSha256 = '2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7'
)

$ErrorActionPreference = 'Stop'
# The bridge is normally launched from a non-interactive Windows PowerShell
# child.  Load this standard module explicitly so the preflight hash check does
# not depend on profile/module-autoload state.
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
if ($DurationSeconds -lt 20 -or $DurationSeconds -gt 180) { throw 'DurationSeconds must be 20..180.' }
if ($GateTimeoutSeconds -lt 20 -or $GateTimeoutSeconds -gt 180) { throw 'GateTimeoutSeconds must be 20..180.' }
$patch = (Resolve-Path -LiteralPath $PatchPath).Path
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash -ne $ExpectedPatchSha256.ToUpperInvariant()) {
  throw 'Local patch hash mismatch.'
}
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
$artifact = (Resolve-Path -LiteralPath $ArtifactDir).Path
$statusPath = Join-Path $artifact 'bridge-status.txt'
$remotePatch = '/sdcard/Android/data/com.example.winavf/files/winavf-image-patch.bin'
$tokenBytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($tokenBytes) } finally { $rng.Dispose() }
# `Convert.ToHexString()` is unavailable in Windows PowerShell 5.1/.NET
# Framework; this equivalent produces the same ASCII hex capability token.
$token = [BitConverter]::ToString($tokenBytes).Replace('-', '')

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net.Sockets;
using System.Threading.Tasks;
public static class WinAvfProductKdRaw {
  public static async Task Pump(Stream source, Stream destination, string logPath, bool append) {
    using (var log = new FileStream(logPath, append ? FileMode.Append : FileMode.Create, FileAccess.Write, FileShare.Read)) {
      var buffer = new byte[16384];
      for (;;) {
        int read = await source.ReadAsync(buffer, 0, buffer.Length);
        if (read <= 0) break;
        await log.WriteAsync(buffer, 0, read); await log.FlushAsync();
        await destination.WriteAsync(buffer, 0, read); await destination.FlushAsync();
      }
    }
  }
  public static void ReadExact(Stream source, byte[] target) {
    int offset = 0;
    while (offset < target.Length) { int n = source.Read(target, offset, target.Length - offset); if (n <= 0) throw new EndOfStreamException(); offset += n; }
  }
  public static bool CopyUntilMarker(NetworkStream source, string marker, string logPath, int timeoutMs) {
    byte[] needle = System.Text.Encoding.ASCII.GetBytes(marker);
    int match = 0;
    source.ReadTimeout = timeoutMs;
    using (var log = new FileStream(logPath, FileMode.Create, FileAccess.Write, FileShare.Read)) {
      byte[] buffer = new byte[16384];
      for (;;) {
        int read = source.Read(buffer, 0, buffer.Length);
        if (read <= 0) return false;
        log.Write(buffer, 0, read); log.Flush();
        for (int i = 0; i < read; ++i) {
          if (buffer[i] == needle[match]) { match++; if (match == needle.Length) {
            // NetworkStream rejects zero: use the documented Infinite timeout
            // after the gate is observed, before starting the raw KD pumps.
            source.ReadTimeout = System.Threading.Timeout.Infinite;
            return true;
          } }
          else { match = buffer[i] == needle[0] ? 1 : 0; }
        }
      }
    }
  }
}
'@

function Invoke-Adb([string[]] $Arguments) {
  & $AdbPath @Arguments
  if ($LASTEXITCODE -ne 0) { throw "adb failed ($LASTEXITCODE): $($Arguments -join ' ')" }
}
function Read-RemoteHash([string] $Path) {
  $line = & $AdbPath exec-out "sha256sum '$Path'" 2>$null
  if ($LASTEXITCODE -ne 0 -or $line -notmatch '^([0-9a-fA-F]{64})\s') { throw "Could not hash Android file: $Path" }
  return $matches[1].ToUpperInvariant()
}

$previousPolicy = $null
$pipe = $null
$kd = $null
$client = $null
try {
  $baseline = Read-RemoteHash $ProductImagePath
  if ($baseline -ne $ExpectedBaselineSha256.ToUpperInvariant()) { throw "Product baseline hash mismatch: $baseline" }
  Add-Content $statusPath "PRODUCT_BASELINE_SHA256=$baseline"
  Invoke-Adb @('push', $patch, $remotePatch)
  $remoteHash = Read-RemoteHash $remotePatch
  if ($remoteHash -ne $ExpectedPatchSha256.ToUpperInvariant()) { throw "Staged patch hash mismatch: $remoteHash" }
  Add-Content $statusPath "PATCH_STAGED_SHA256=$remoteHash"

  $previousPolicy = (& $AdbPath shell settings get global hidden_api_policy 2>$null).Trim()
  if ([string]::IsNullOrWhiteSpace($previousPolicy) -or $previousPolicy -eq 'null') { $previousPolicy = $null }
  Invoke-Adb @('shell', 'settings', 'put', 'global', 'hidden_api_policy', '1')
  Add-Content $statusPath "HIDDEN_API_POLICY_TEMPORARY=1"
  # Hidden-API access is evaluated when the app process resolves the method.
  # Ensure the following bridge launch is a fresh process under policy=1.
  Invoke-Adb @('shell', 'am', 'force-stop', 'com.example.winavf')
  # `adb forward --remove` emits an error when there is no old listener.  That
  # is normal on a clean run and must not abort the transaction before the app
  # has even started.
  $existingForwards = (& $AdbPath forward --list 2>$null) -join "`n"
  if ($existingForwards -match '(?m)\btcp:39100\b') {
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $AdbPath forward --remove tcp:39100 2>$null | Out-Null }
    finally { $ErrorActionPreference = $savedErrorActionPreference }
  }
  Invoke-Adb @('forward', 'tcp:39100', 'tcp:39100')
  Invoke-Adb @('shell', 'rm', '-f', '/sdcard/Android/data/com.example.winavf/files/rollback-report.txt', '/sdcard/Android/data/com.example.winavf/files/product-kd-bridge-report.txt')

  Invoke-Adb @('shell', 'am', 'start', '-n', 'com.example.winavf/.MainActivity', '--ez', 'kd_bridge', 'true', '--es', 'kd_token', $token)
  # A local adb-forward listener can accept TCP before the Android Activity has
  # bound its remote ServerSocket.  Wait for the app's own durable readiness
  # record; the app accepts one bridge peer only, so do not use speculative
  # connects as a readiness probe.
  $listenerDeadline = [DateTime]::UtcNow.AddSeconds(20)
  $listenerReady = $false
  while ([DateTime]::UtcNow -lt $listenerDeadline) {
    $listenerReport = ((& $AdbPath shell cat /sdcard/Android/data/com.example.winavf/files/product-kd-bridge-report.txt 2>$null) -join "`n")
    if ($listenerReport -match 'state=LISTENING') { $listenerReady = $true; break }
    Start-Sleep -Milliseconds 250
  }
  if (-not $listenerReady) { throw 'The Android product KD listener did not report readiness.' }
  Add-Content $statusPath 'ANDROID_BRIDGE_LISTENING=1'

  $deadline = [DateTime]::UtcNow.AddSeconds(20)
  while ($null -eq $client -and [DateTime]::UtcNow -lt $deadline) {
    try { $candidate = [Net.Sockets.TcpClient]::new(); $candidate.NoDelay = $true; $candidate.Connect('127.0.0.1', 39100); $client = $candidate } catch { if ($candidate) { $candidate.Dispose() }; Start-Sleep -Milliseconds 250 }
  }
  if ($null -eq $client) { throw 'The Android product KD listener did not accept a localhost connection.' }
  $network = $client.GetStream()
  $tokenBytes = [Text.Encoding]::ASCII.GetBytes($token)
  $network.Write($tokenBytes, 0, $tokenBytes.Length); $network.Flush()
  $greeting = [byte[]]::new(20); [WinAvfProductKdRaw]::ReadExact($network, $greeting)
  if ([Text.Encoding]::ASCII.GetString($greeting) -ne "WINAVF_KD_BRIDGE_OK`n") { throw 'Unexpected Android KD bridge greeting.' }
  Add-Content $statusPath "ANDROID_BRIDGE_AUTHENTICATED=1"

  # U-Boot owns ttyS0 until it hands off.  Do not create KD or forward one
  # host byte until output proves it has reached the Windows loader.
  Add-Content $statusPath "GATE_WAITING_FOR=$GateMarker"
  try {
    $opened = [WinAvfProductKdRaw]::CopyUntilMarker($network, $GateMarker, (Join-Path $artifact 'raw-guest-to-kd.bin'), $GateTimeoutSeconds * 1000)
  } catch [IO.IOException] { $opened = $false }
  if (-not $opened) { throw "Gate marker was not observed within $GateTimeoutSeconds seconds: $GateMarker" }
  Add-Content $statusPath "GATE_MARKER_OBSERVED=$GateMarker"

  $pipe = [IO.Pipes.NamedPipeServerStream]::new($PipeName, [IO.Pipes.PipeDirection]::InOut, 1, [IO.Pipes.PipeTransmissionMode]::Byte, [IO.Pipes.PipeOptions]::Asynchronous)
  Add-Content $statusPath "PIPE_LISTENING=$PipeName"
  $kdArgs = "-b -logo `"$(Join-Path $artifact 'kd.log.txt')`" -k `"com:pipe,port=\\.\pipe\$PipeName,baud=115200,resets=0,reconnect`""
  $kd = Start-Process -FilePath $KdPath -ArgumentList $kdArgs -PassThru -WindowStyle Hidden
  $pipeWait = $pipe.WaitForConnectionAsync()
  if (-not $pipeWait.Wait(15000)) { throw 'KD did not connect to the host named pipe after the gate opened.' }
  Add-Content $statusPath "KD_PIPE_CONNECTED=1"
  $tx = [WinAvfProductKdRaw]::Pump($pipe, $network, (Join-Path $artifact 'raw-kd-to-guest.bin'), $false)
  $rx = [WinAvfProductKdRaw]::Pump($network, $pipe, (Join-Path $artifact 'raw-guest-to-kd.bin'), $true)
  Add-Content $statusPath "RAW_KD_BRIDGE_RUNNING_UTC=$([DateTime]::UtcNow.ToString('O'))"
  Start-Sleep -Seconds $DurationSeconds
  Add-Content $statusPath "BOUND_REACHED=SECONDS_$DurationSeconds"
} finally {
  try { Invoke-Adb @('shell', 'am', 'start', '-n', 'com.example.winavf/.MainActivity', '--ez', 'kd_bridge_stop', 'true') } catch { }
  try {
    $stopDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $stopDeadline) {
      $vms = (& $AdbPath shell vm list 2>$null) -join "`n"
      if ($vms -notmatch 'winavf-gop-ebs-r1') { break }
      Start-Sleep -Seconds 1
    }
  } catch { }
  # A VM is owned by the app process.  Force-stopping that one diagnostic app
  # is the previously proven way to guarantee VM teardown before opening the
  # private disk for rollback; it never touches Android system services/data.
  try { Invoke-Adb @('shell', 'am', 'force-stop', 'com.example.winavf'); Add-Content $statusPath 'APP_FORCE_STOP_FOR_ROLLBACK=1'; Start-Sleep -Seconds 2 } catch { }
  try { if ($client) { $client.Dispose() } } catch { }
  try { if ($pipe) { $pipe.Dispose() } } catch { }
  try { if ($kd -and -not $kd.HasExited) { $kd.Kill() } } catch { }
  try { Invoke-Adb @('forward', '--remove', 'tcp:39100') } catch { }
  try {
    Invoke-Adb @('shell', 'am', 'start', '-n', 'com.example.winavf/.MainActivity', '--ez', 'rollback', 'true')
    $rollbackDeadline = [DateTime]::UtcNow.AddSeconds(75)
    $rollbackResult = ''
    while ([DateTime]::UtcNow -lt $rollbackDeadline) {
      $rollbackResult = (& $AdbPath shell cat /sdcard/Android/data/com.example.winavf/files/rollback-report.txt 2>$null) -join "`n"
      if ($rollbackResult -match 'RESULT=(PASS|FAIL)') { break }
      Start-Sleep -Seconds 2
    }
    $rollbackResult | Set-Content -LiteralPath (Join-Path $artifact 'rollback-report.txt') -Encoding ascii
    if ($rollbackResult -notmatch 'RESULT=PASS' -or $rollbackResult -notmatch "BASELINE_SHA256=$ExpectedBaselineSha256") { throw 'Transactional rollback did not report an exact baseline restoration.' }
    $afterRollback = Read-RemoteHash $ProductImagePath
    if ($afterRollback -ne $ExpectedBaselineSha256.ToUpperInvariant()) { throw "Product source baseline hash changed after rollback: $afterRollback" }
    Add-Content $statusPath "ROLLBACK_BASELINE_SHA256=$afterRollback"
  } catch { Add-Content $statusPath "ROLLBACK_FAILED=$($_.Exception.Message)" }
  try {
    if ($null -eq $previousPolicy) { Invoke-Adb @('shell', 'settings', 'delete', 'global', 'hidden_api_policy') }
    else { Invoke-Adb @('shell', 'settings', 'put', 'global', 'hidden_api_policy', $previousPolicy) }
    $restored = if ($null -eq $previousPolicy) { 'null' } else { $previousPolicy }
    Add-Content $statusPath "HIDDEN_API_POLICY_RESTORED=$restored"
  } catch { Add-Content $statusPath "HIDDEN_API_POLICY_RESTORE_FAILED=$($_.Exception.Message)" }
}

Write-Host "Prepared/finished bounded product KD bridge artifacts: $artifact"

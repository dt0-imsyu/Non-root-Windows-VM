<#
Minimal host-side ADB executor for the product KD workflow.

This file is intended to be run on the Windows host outside the agent sandbox.
It deliberately exposes a finite operation allowlist and never evaluates a
PowerShell command supplied by the caller. Every invocation is JSONL logged.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet(
    'baseline_check','vm_list','get_hidden_api_policy','adb_shell','push',
    'pull','install','start_vm','stop_vm','rollback','capture_serial','capture_kd'
  )][string] $Operation,
  [string] $AdbPath = 'C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe',
  [string] $Source,
  [string] $Destination,
  [string[]] $Arguments = @(),
  [string] $ArtifactDir = '.\build-logs\adb-allowlist',
  [string] $LogPath
)

$ErrorActionPreference = 'Stop'
$productImage = '/sdcard/Android/data/com.example.winavf/files/win11-gop-ebs-r1.img'
$expectedPatchSha = '4F2EA0AE40E6467608EA753E1368EC3F97C03A4C11DA9B2A17782D62B93742E6'
$rollbackReport = '/sdcard/Android/data/com.example.winavf/files/rollback-report.txt'
$bridgeReport = '/sdcard/Android/data/com.example.winavf/files/product-kd-bridge-report.txt'
$remotePatch = '/sdcard/Android/data/com.example.winavf/files/winavf-image-patch.bin'
$serialLog = '/sdcard/Android/data/com.example.winavf/files/serial.log'
$bridgeRx = '/sdcard/Android/data/com.example.winavf/files/product-kd-bridge-rx.bin'
$bridgeTx = '/sdcard/Android/data/com.example.winavf/files/product-kd-bridge-tx.bin'
$app = 'com.example.winavf'

if (-not (Test-Path -LiteralPath $AdbPath -PathType Leaf)) { throw "ADB executable not found: $AdbPath" }
$null = New-Item -ItemType Directory -Force -Path $ArtifactDir
if (-not $LogPath) { $LogPath = Join-Path (Resolve-Path $ArtifactDir) 'operations.jsonl' }

function Write-Record([hashtable] $Record) {
  $Record.timestamp_utc = [DateTime]::UtcNow.ToString('O')
  ($Record | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $LogPath -Encoding utf8
}

function Invoke-AdbSafe([string[]] $AdbArgs) {
  if ($null -eq $AdbArgs -or $AdbArgs.Count -eq 0 -or @($AdbArgs | Where-Object { $null -eq $_ }).Count -gt 0) {
    throw 'ADB argument list contains a null or empty element.'
  }
  $safeArgs = @($AdbArgs | ForEach-Object { [string]$_ })
  $stdoutFile = [IO.Path]::GetTempFileName()
  $stderrFile = [IO.Path]::GetTempFileName()
  try {
    $p = Start-Process -FilePath $AdbPath -ArgumentList $safeArgs -NoNewWindow -Wait -PassThru `
      -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    $stdout = Get-Content -Raw -LiteralPath $stdoutFile -ErrorAction SilentlyContinue
    $stderr = Get-Content -Raw -LiteralPath $stderrFile -ErrorAction SilentlyContinue
    if ($null -eq $stdout) { $stdout = '' }
    if ($null -eq $stderr) { $stderr = '' }
    return [pscustomobject]@{ stdout = $stdout; stderr = $stderr; exit_code = $p.ExitCode }
  } finally {
    Remove-Item -LiteralPath $stdoutFile,$stderrFile -Force -ErrorAction SilentlyContinue
  }
}

function Complete([string[]] $AdbArgs, [switch] $ReadOnly) {
  $result = Invoke-AdbSafe $AdbArgs
  Write-Record @{ operation = $Operation; read_only = [bool]$ReadOnly; adb_args = $AdbArgs; result = $result }
  $result | ConvertTo-Json -Depth 8
  if ($result.exit_code -ne 0) { exit $result.exit_code }
}

function Invoke-Step([string[]] $AdbArgs, [switch] $ReadOnly) {
  $result = Invoke-AdbSafe $AdbArgs
  Write-Record @{ operation = $Operation; read_only = [bool]$ReadOnly; adb_args = $AdbArgs; result = $result }
  return $result
}

function Assert-LocalInput([string] $Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Local input does not exist: $Path" }
}

function Assert-RemoteDestination([string] $Path) {
  if ($Path -ne $remotePatch) { throw "Remote destination is not allowlisted: $Path" }
}

function Assert-NoShellMeta([string[]] $Values) {
  foreach ($value in $Values) {
    if ($value -match '[;&|<>`$()\r\n]') { throw 'Shell metacharacters are not accepted.' }
  }
}

switch ($Operation) {
  'baseline_check' {
    Complete @('shell','sha256sum', $productImage) $true
    Complete @('shell','vm','list') $true
    Complete @('shell','settings','get','global','hidden_api_policy') $true
  }
  'vm_list' { Complete @('shell','vm','list') $true }
  'get_hidden_api_policy' { Complete @('shell','settings','get','global','hidden_api_policy') $true }
  'adb_shell' {
    if (-not $Arguments.Count) { throw 'Arguments are required for adb_shell.' }
    Assert-NoShellMeta $Arguments
    $allowed = @(
      '^sha256sum$', '^cat$', '^vm$', '^list$', '^settings$', '^get$',
      '^global$', '^hidden_api_policy$', '^am$', '^force-stop$', '^start$', '^rm$', '^-f$',
      '^com\.example\.winavf(?:/.MainActivity)?$', '^rollback-report\.txt$', '^product-kd-bridge-report\.txt$',
      '^1$', '^0$'
    )
    foreach ($arg in $Arguments) {
      $knownPath = $arg -in @($productImage,$rollbackReport,$bridgeReport,$remotePatch)
      if (-not $knownPath -and -not ($allowed | Where-Object { $arg -match $_ })) { throw "adb_shell argument is not allowlisted: $arg" }
    }
    Complete (@('shell') + $Arguments)
  }
  'push' {
    if (-not $Source -or -not $Destination) { throw 'Source and Destination are required.' }
    Assert-LocalInput $Source; Assert-RemoteDestination $Destination
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash -ne $expectedPatchSha) { throw 'Only the audited product KD patch may be pushed.' }
    Complete @('push',$Source,$Destination)
  }
  'pull' { if (-not $Source -or -not $Destination) { throw 'Source and Destination are required.' }; if ($Source -notin @($rollbackReport,$bridgeReport,$serialLog,$bridgeRx,$bridgeTx)) { throw "Remote source is not allowlisted: $Source" }; $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination); Complete @('pull',$Source,$Destination) }
  'install' {
    if (-not $Source) { throw 'Source APK is required.' }
    Assert-LocalInput $Source
    if ([IO.Path]::GetFileName($Source) -ne 'WinAVF-test.apk') { throw 'Only WinAVF-test.apk may be installed.' }
    Complete @('install','-r',$Source)
  }
  'start_vm' { Complete @('shell','am','start','-n',"$app/.MainActivity",'--ez','start','true') }
  'stop_vm' { Complete @('shell','am','force-stop',$app) }
  'rollback' {
    $steps = @(
      (Invoke-Step @('shell','am','force-stop',$app)),
      (Start-Sleep -Seconds 2),
      (Invoke-Step @('shell','am','start','-n',"$app/.MainActivity",'--ez','rollback','true')),
      (Invoke-Step @('shell','cat',$rollbackReport)),
      (Invoke-Step @('shell','sha256sum',$productImage) -ReadOnly),
      (Invoke-Step @('shell','vm','list') -ReadOnly),
      (Invoke-Step @('shell','settings','get','global','hidden_api_policy') -ReadOnly)
    )
    $failed = $steps | Where-Object { $_ -and $_.exit_code -ne 0 }
    if ($failed) { exit 1 }
  }
  'capture_serial' {
    if (-not $Destination) { throw 'Destination is required.' }
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination)
    Complete @('pull',$serialLog,$Destination)
  }
  'capture_kd' {
    if (-not $Destination) { throw 'Destination is required.' }
    $dir = New-Item -ItemType Directory -Force -Path $Destination
    Complete @('pull',$bridgeReport,(Join-Path $dir.FullName 'product-kd-bridge-report.txt'))
    Complete @('pull',$bridgeRx,(Join-Path $dir.FullName 'product-kd-bridge-rx.bin'))
    Complete @('pull',$bridgeTx,(Join-Path $dir.FullName 'product-kd-bridge-tx.bin'))
  }
}

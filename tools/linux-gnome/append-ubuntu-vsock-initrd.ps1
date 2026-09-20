[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $SourceInitrd,
  [Parameter(Mandatory = $true)] [string] $ProbePath,
  [string] $OutputInitrd = 'C:\Users\denis\MainProjects\win11ontab\build-logs\ubuntu-gnome-vsock\initrd-with-winavf-vsock',
  [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\ubuntu-gnome-vsock\initrd-append-report.txt'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$hookPath = Join-Path $PSScriptRoot 'guest\99-winavf-vsock'
foreach ($path in @($SourceInitrd, $ProbePath, $hookPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required input: $path" }
}
if ((Get-Item -LiteralPath $SourceInitrd).Length -lt 1MB) { throw 'Source initrd is unexpectedly small.' }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputInitrd), (Split-Path -Parent $ReportPath) | Out-Null
if (Test-Path -LiteralPath $OutputInitrd) { Remove-Item -LiteralPath $OutputInitrd -Force }

function Write-Ascii([IO.Stream] $stream, [string] $text) {
  $bytes = [Text.Encoding]::ASCII.GetBytes($text)
  $stream.Write($bytes, 0, $bytes.Length)
}
function Write-Padding([IO.Stream] $stream, [int64] $length) {
  $pad = (4 - ($length % 4)) % 4
  if ($pad) { $stream.Write((New-Object byte[] $pad), 0, $pad) }
}
function Write-NewcEntry([IO.Stream] $stream, [string] $path, [byte[]] $content, [int] $mode, [int] $inode) {
  $nameBytes = [Text.Encoding]::ASCII.GetBytes($path + [char]0)
  $header = '070701{0:X8}{1:X8}{2:X8}{3:X8}{4:X8}{5:X8}{6:X8}{7:X8}{8:X8}{9:X8}{10:X8}{11:X8}{12:X8}' -f $inode, $mode, 0, 0, 1, 0, $content.Length, 0, 0, 0, 0, $nameBytes.Length, 0
  Write-Ascii $stream $header
  $stream.Write($nameBytes, 0, $nameBytes.Length)
  Write-Padding $stream (110 + $nameBytes.Length)
  if ($content.Length) { $stream.Write($content, 0, $content.Length) }
  Write-Padding $stream $content.Length
}
function Read-Exact([IO.Stream] $stream, [int] $count) {
  $buffer = New-Object byte[] $count
  $offset = 0
  while ($offset -lt $count) {
    $read = $stream.Read($buffer, $offset, $count - $offset)
    if ($read -le 0) { throw 'Unexpected EOF while auditing appended newc layer.' }
    $offset += $read
  }
  return $buffer
}
function Read-AppendedNewcNames([string] $path, [int64] $start) {
  $names = [System.Collections.Generic.List[string]]::new()
  $stream = [IO.File]::OpenRead($path)
  try {
    $stream.Position = $start
    while ($true) {
      $header = [Text.Encoding]::ASCII.GetString((Read-Exact $stream 110))
      if (-not $header.StartsWith('070701')) { throw 'Appended layer does not begin with a newc header.' }
      $fileSize = [Convert]::ToInt32($header.Substring(54, 8), 16)
      $nameSize = [Convert]::ToInt32($header.Substring(94, 8), 16)
      $name = [Text.Encoding]::ASCII.GetString((Read-Exact $stream $nameSize)).TrimEnd([char]0)
      $names.Add($name)
      $namePad = (4 - ((110 + $nameSize) % 4)) % 4
      if ($namePad) { [void](Read-Exact $stream $namePad) }
      if ($fileSize) { [void](Read-Exact $stream $fileSize) }
      $filePad = (4 - ($fileSize % 4)) % 4
      if ($filePad) { [void](Read-Exact $stream $filePad) }
      if ($name -eq 'TRAILER!!!') { return $names }
    }
  } finally { $stream.Dispose() }
}

$probe = [IO.File]::ReadAllBytes($ProbePath)
$hook = [IO.File]::ReadAllBytes($hookPath)
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceInitrd).Hash.ToUpperInvariant()
try {
  $input = [IO.File]::Open($SourceInitrd, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  $output = [IO.File]::Open($OutputInitrd, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try {
    $buffer = New-Object byte[] 4MB
    while (($count = $input.Read($buffer, 0, $buffer.Length)) -gt 0) { $output.Write($buffer, 0, $count) }
    # Linux initramfs accepts concatenated archives.  The original Ubuntu
    # initrd remains byte-for-byte unchanged; this is one trailing newc layer.
    Write-NewcEntry $output 'scripts/init-premount/99-winavf-vsock' $hook 0x81ED 1
    Write-NewcEntry $output 'usr/local/sbin/winavf-vsock-hello' $probe 0x81ED 2
    Write-NewcEntry $output 'TRAILER!!!' ([byte[]]@()) 0 3
    $output.Flush($true)
  } finally { $output.Dispose(); $input.Dispose() }
} catch { if (Test-Path -LiteralPath $OutputInitrd) { Remove-Item -LiteralPath $OutputInitrd -Force }; throw }

$outputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputInitrd).Hash.ToUpperInvariant()
$entries = Read-AppendedNewcNames $OutputInitrd ([int64](Get-Item -LiteralPath $SourceInitrd).Length)
$expectedEntries = @('scripts/init-premount/99-winavf-vsock', 'usr/local/sbin/winavf-vsock-hello', 'TRAILER!!!')
if ((Compare-Object -ReferenceObject $expectedEntries -DifferenceObject $entries)) { throw 'Appended newc layer content audit failed.' }
@(
  'RESULT=PASS',
  'CHANGE=Appended one newc layer only',
  "SOURCE_INITRD_SHA256=$sourceHash",
  "OUTPUT_INITRD_SHA256=$outputHash",
  "SOURCE_BYTES=$((Get-Item -LiteralPath $SourceInitrd).Length)",
  "OUTPUT_BYTES=$((Get-Item -LiteralPath $OutputInitrd).Length)",
  "PROBE_SHA256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $ProbePath).Hash.ToUpperInvariant())",
  'HOOK=scripts/init-premount/99-winavf-vsock',
  'LISTENER=usr/local/sbin/winavf-vsock-hello',
  'APPENDED_NEWC_AUDIT=PASS',
  'PORT=4051',
  'NEXT=Replace only CASPER\\INITRD in a new disposable Ubuntu raw candidate, then audit before Android staging.'
) | Set-Content -LiteralPath $ReportPath -Encoding utf8
Get-Content -LiteralPath $ReportPath

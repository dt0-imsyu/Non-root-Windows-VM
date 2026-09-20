[CmdletBinding()]
param(
  [string] $OutputPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\ubuntu-gnome-vsock\winavf-vsock-hello',
  [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\ubuntu-gnome-vsock\build-probe-report.txt'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$toolchain = 'C:\Users\denis\MainProjects\win11ontab\tools\arm-gnu-toolchain-15.2\bin'
$gcc = Join-Path $toolchain 'aarch64-none-elf-gcc.exe'
$readelf = Join-Path $toolchain 'aarch64-none-elf-readelf.exe'
$source = Join-Path $PSScriptRoot 'guest\winavf_vsock_hello.S'

foreach ($path in @($gcc, $readelf, $source)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required build input: $path" }
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath), (Split-Path -Parent $ReportPath) | Out-Null
if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }

& $gcc '-nostdlib' '-static' '-Wl,--build-id=none' '-Wl,-e,_start' '-o' $OutputPath $source
if ($LASTEXITCODE -ne 0) { throw 'Linux/ARM64 vsock probe build failed.' }
$headers = & $readelf -h $OutputPath 2>&1
$headerText = $headers -join "`n"
if ($LASTEXITCODE -ne 0 -or $headerText -notmatch 'Machine:\s+AArch64' -or $headerText -notmatch 'Type:\s+EXEC') {
  throw 'Output is not a static ARM64 executable.'
}
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPath).Hash.ToUpperInvariant()
@(
  'RESULT=PASS',
  'TARGET=Linux ARM64 static AF_VSOCK listener',
  'PORT=4051',
  "PROBE_PATH=$OutputPath",
  "PROBE_SHA256=$sha",
  'ELF_AARCH64=PASS',
  'ELF_STATIC_EXEC=PASS',
  'NEXT=Append this probe and its init-premount hook to a disposable Ubuntu initrd only.'
) | Set-Content -LiteralPath $ReportPath -Encoding utf8
Get-Content -LiteralPath $ReportPath

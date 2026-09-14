<# Read-only post-stop inspector for SETUPACT.LOG / SETUPERR.LOG on a clone. #>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string] $RawPath,
  [string] $MtoolsBin = 'C:\msys64\mingw64\bin',
  [string] $ArtifactDir = 'C:\Users\denis\MainProjects\win11ontab\build-logs\persistent-boot-witness-20260909\offline-inspection'
)

$ErrorActionPreference = 'Stop'
$fatOffset = 1048576L
foreach ($path in @($RawPath, (Join-Path $MtoolsBin 'mdir.exe'), (Join-Path $MtoolsBin 'mcopy.exe'))) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Required path is missing: $path" }
}
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null
$spec = "$RawPath@@$fatOffset"
$mdir = Join-Path $MtoolsBin 'mdir.exe'
$mcopy = Join-Path $MtoolsBin 'mcopy.exe'
$root = (& $mdir -i $spec -a ::) -join "`n"
$root | Set-Content -LiteralPath (Join-Path $ArtifactDir 'fat-root-after-stop.txt') -Encoding ascii

$found = @()
foreach ($name in @('setupact.log', 'setuperr.log')) {
  $destination = Join-Path $ArtifactDir $name
  Push-Location $ArtifactDir
  try { & $mcopy -o -i $spec "::/$name" (".\\$name") 2>$null } finally { Pop-Location }
  if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $destination) -and (Get-Item -LiteralPath $destination).Length -gt 0) {
    $found += $name
  }
}

$status = if ($found.Count -gt 0) { 'PASS' } else { 'NOT_OBSERVED' }
$result = @(
  "PERSISTENT_WINDOWS_SETUP_WITNESS=$status",
  (if ($status -eq 'PASS') { 'WINDOWS_KERNEL_EXECUTION_AFTER_EBS=PASS' } else { 'WINDOWS_KERNEL_EXECUTION_AFTER_EBS=NOT_OBSERVED' }),
  'NEGATIVE_INTERPRETATION=NO_PERSISTENT_ARTIFACT_DOES_NOT_PROVE_NO_KERNEL_EXECUTION',
  "RAW_SHA256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $RawPath).Hash)",
  "FOUND=$($found -join ',')"
)
foreach ($name in $found) {
  $file = Join-Path $ArtifactDir $name
  $result += "$(($name).ToUpperInvariant())_BYTES=$((Get-Item -LiteralPath $file).Length)"
  $result += "$(($name).ToUpperInvariant())_SHA256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash)"
}
$result | Set-Content -LiteralPath (Join-Path $ArtifactDir 'persistent-witness-result.txt') -Encoding ascii
Get-Content -LiteralPath (Join-Path $ArtifactDir 'persistent-witness-result.txt')

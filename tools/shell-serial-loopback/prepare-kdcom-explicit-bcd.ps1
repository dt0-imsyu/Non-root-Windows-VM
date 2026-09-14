<#
Creates a disposable BCD candidate for one shell-owned KD A/B.
It changes no Android media, firmware, WIM, or product baseline.
Run from an elevated PowerShell prompt.
#>
[CmdletBinding()]
param(
  [string] $Source = 'C:\Users\denis\MainProjects\win11ontab\build-logs\kd-shell-clone-20260907\BCD.kd-serial',
  [string] $CandidatePath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\kd-shell-kdcom-bcd-20260907\BCD.kdcom-explicit'
)

$ErrorActionPreference = 'Stop'
$expectedSourceHash = 'DE6698BF9CCF5205403A5E8ED1D6CC5E2790A3E3EF23F4539B512D1C0DFB9A11'

if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
  throw "Source BCD is missing: $Source"
}

$actualSourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
if ($actualSourceHash -ne $expectedSourceHash) {
  throw "Unexpected source BCD SHA-256: $actualSourceHash"
}

if (Test-Path -LiteralPath $CandidatePath) {
  throw "Refusing to overwrite existing candidate: $CandidatePath"
}

$candidateDirectory = [System.IO.Path]::GetDirectoryName($CandidatePath)
if ([string]::IsNullOrWhiteSpace($candidateDirectory)) {
  throw "Candidate path has no directory component: $CandidatePath"
}
New-Item -ItemType Directory -Path $candidateDirectory -Force | Out-Null
Copy-Item -LiteralPath $Source -Destination $CandidatePath

& bcdedit /store $CandidatePath /set '{default}' dbgtransport kdcom.dll
if ($LASTEXITCODE -ne 0) {
  throw "bcdedit failed with exit code $LASTEXITCODE"
}

$enum = & bcdedit /store $CandidatePath /enum all
if ($LASTEXITCODE -ne 0) {
  throw "bcdedit /enum failed with exit code $LASTEXITCODE"
}

$enum | Set-Content -LiteralPath "$CandidatePath.enum.txt" -Encoding utf8
$enumText = $enum -join "`n"
if ($enumText -notmatch 'dbgtransport\s+kdcom\.dll') {
  throw 'Explicit kdcom.dll transport was not persisted.'
}

$bootMgr = & bcdedit /store $CandidatePath /enum '{bootmgr}'
if ($LASTEXITCODE -ne 0) {
  throw "bcdedit /enum {bootmgr} failed with exit code $LASTEXITCODE"
}
$bootMgr | Set-Content -LiteralPath "$CandidatePath.bootmgr.enum.txt" -Encoding utf8
$bootMgrText = $bootMgr -join "`n"
if ($bootMgrText -match 'bootdebug\s+Yes') {
  throw '{bootmgr}.bootdebug must remain disabled for this A/B.'
}

[pscustomobject]@{
  Source = $Source
  SourceSha256 = $actualSourceHash
  Candidate = $CandidatePath
  CandidateSha256 = (Get-FileHash -LiteralPath $CandidatePath -Algorithm SHA256).Hash
  DefaultDbgTransport = 'kdcom.dll'
  BootMgrBootDebug = 'off'
  Result = 'PASS'
} | Format-List

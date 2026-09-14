<#
Creates one disposable raw candidate for the persistent Windows Setup witness.
It refuses to overwrite an existing destination and never opens a physical
disk.  The only media delta is root-level Autounattend.xml on a byte-for-byte
copy of the immutable baseline.  mtools performs the FAT write.
#>
[CmdletBinding()]
param(
  [string] $SourceRaw = 'E:\winavf-a3-append-only-runtime.img',
  [string] $ExpectedBaselineSha256 = '2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7',
  [string] $CandidateRaw = 'E:\winavf-persistent-witness-candidate-20260909.img',
  [string] $MtoolsBin = 'C:\msys64\mingw64\bin',
  [string] $WitnessXml = (Join-Path $PSScriptRoot 'Autounattend.xml'),
  [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\persistent-boot-witness-20260909\materialize-report.txt'
)

$ErrorActionPreference = 'Stop'
$fatOffset = 1048576L
$expectedBytes = 9126805504L
foreach ($path in @($SourceRaw, $WitnessXml, (Join-Path $MtoolsBin 'mcopy.exe'), (Join-Path $MtoolsBin 'mdir.exe'))) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Required path is missing: $path" }
}
if (Test-Path -LiteralPath $CandidateRaw) { throw "Refusing to overwrite existing candidate: $CandidateRaw" }
if ((Get-Item -LiteralPath $SourceRaw).Length -ne $expectedBytes) { throw 'Unexpected baseline image length.' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $SourceRaw).Hash -ne $ExpectedBaselineSha256.ToUpperInvariant()) {
  throw 'Exact immutable baseline SHA-256 mismatch.'
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $CandidateRaw), (Split-Path -Parent $ReportPath) | Out-Null
Copy-Item -LiteralPath $SourceRaw -Destination $CandidateRaw -ErrorAction Stop
$imageSpec = "$CandidateRaw@@$fatOffset"
$mdir = Join-Path $MtoolsBin 'mdir.exe'
$mcopy = Join-Path $MtoolsBin 'mcopy.exe'

# Static precondition: this witness must not pre-exist on baseline or candidate.
$rootBefore = (& $mdir -i $imageSpec -a ::) -join "`n"
if ($rootBefore -match '(?im)^\s*setupact\s+log\b|^\s*setuperr\s+log\b|autounattend\s+xml\b') {
  throw 'Baseline unexpectedly already contains a witness or answer file.'
}

Push-Location (Split-Path -Parent $WitnessXml)
try {
  # mtools treats a drive-letter path as an mtools drive; copy from the current
  # directory to avoid that ambiguity.
  & $mcopy -o -i $imageSpec '.\Autounattend.xml' '::/Autounattend.xml'
  if ($LASTEXITCODE -ne 0) { throw 'mcopy failed while writing Autounattend.xml.' }
} finally { Pop-Location }

$verifyDir = Join-Path (Split-Path -Parent $ReportPath) 'verify'
New-Item -ItemType Directory -Force -Path $verifyDir | Out-Null
Push-Location $verifyDir
try {
  & $mcopy -o -i $imageSpec '::/Autounattend.xml' '.\Autounattend.xml'
  if ($LASTEXITCODE -ne 0) { throw 'mcopy failed while reading back Autounattend.xml.' }
} finally { Pop-Location }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $WitnessXml).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $verifyDir 'Autounattend.xml')).Hash) {
  throw 'Autounattend.xml read-back SHA-256 mismatch.'
}

$candidateHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateRaw).Hash
@(
  'RESULT=PASS',
  "BASELINE_RAW=$SourceRaw",
  "BASELINE_SHA256=$ExpectedBaselineSha256",
  "CANDIDATE_RAW=$CandidateRaw",
  "CANDIDATE_BYTES=$((Get-Item -LiteralPath $CandidateRaw).Length)",
  "CANDIDATE_SHA256=$candidateHash",
  'FAT_OFFSET=1048576',
  "AUTOUNATTEND_SHA256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $WitnessXml).Hash)",
  'STATIC_WITNESS_ABSENT_BEFORE=PASS',
  'AUTOUNATTEND_READBACK=PASS',
  'ONLY_INTENDED_SEMANTIC_MEDIA_CHANGE=ROOT_AUTOUNATTEND_XML'
) | Set-Content -LiteralPath $ReportPath -Encoding ascii
Get-Content -LiteralPath $ReportPath

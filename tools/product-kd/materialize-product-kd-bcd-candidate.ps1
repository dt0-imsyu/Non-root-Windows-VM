<#
Run ONCE from an elevated PowerShell window.

Creates an isolated fixed VHD from the exact local product baseline and uses
only the Windows storage/FAT stack to replace EFI\Microsoft\Boot\BCD with the
already audited serial-KD candidate.  It never opens the Android tablet image,
never touches a physical disk, and refuses all pre-existing outputs.
#>
[CmdletBinding()]
param(
  # This is the only locally retained raw whose current full SHA-256 is the
  # immutable product baseline.  The similarly named shell "baseline" file
  # now contains an old KD candidate and is deliberately not used.
  [string] $SourceRaw = 'E:\winavf-a3-append-only-runtime.img',
  [string] $BcdCandidate = 'C:\Users\denis\MainProjects\win11ontab\Non-root-Windows-VM\build-logs\shell-windows-kd-bootmgr-runtime-20260907\mtools\BCD.source-current',
  [string] $VhdPath = 'D:\winavf-product-kd-bcd-work-fixed.vhd',
  [string] $OutputRaw = 'E:\winavf-product-kd-bcd-candidate-20260909.img',
  [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\Non-root-Windows-VM\build-logs\product-kd-preflight-20260909\materialize-product-kd-bcd-candidate.report.txt'
)

$ErrorActionPreference = 'Stop'
$expectedBaseline = '2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7'
$expectedBcd = 'DE6698BF9CCF5205403A5E8ED1D6CC5E2790A3E3EF23F4539B512D1C0DFB9A11'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script from an elevated PowerShell window.' }
if (Test-Path -LiteralPath $VhdPath) { throw "Refusing to overwrite VHD: $VhdPath" }
if (Test-Path -LiteralPath $OutputRaw) { throw "Refusing to overwrite raw candidate: $OutputRaw" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $SourceRaw).Hash -ne $expectedBaseline) { throw 'Exact product baseline SHA-256 mismatch.' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $BcdCandidate).Hash -ne $expectedBcd) { throw 'KD BCD candidate SHA-256 mismatch.' }

$script = Join-Path $PSScriptRoot '..\shell-serial-loopback\materialize-kd-bcd-clone.ps1'
& $script -SourceRaw $SourceRaw -SourceSha256 $expectedBaseline -BcdCandidate $BcdCandidate -BcdSha256 $expectedBcd -VhdPath $VhdPath -OutputRaw $OutputRaw -ReportPath $ReportPath
if ($LASTEXITCODE -ne 0) { throw "VHD materialization failed: $LASTEXITCODE" }
if ((Get-Item -LiteralPath $OutputRaw).Length -ne 9126805504L) { throw 'Candidate raw length mismatch.' }
[pscustomobject]@{
  Result = 'PASS'
  SourceRaw = $SourceRaw
  SourceSha256 = $expectedBaseline
  BcdSha256 = $expectedBcd
  CandidateRaw = $OutputRaw
  CandidateBytes = (Get-Item -LiteralPath $OutputRaw).Length
  VhdRetainedForInspection = $VhdPath
  Next = 'Return to Codex; do not apply or copy this candidate to Android.'
} | Format-List

param(
  [Parameter(Mandatory=$true)][string]$SourceWim,
  [Parameter(Mandatory=$true)][string]$AgentExe,
  [Parameter(Mandatory=$true)][string]$OutputWim,
  [Parameter(Mandatory=$true)][string]$WorkDirectory
)

# Append-only test candidate. Source already contains the signed viosock package.
# Only WinAvfInput.exe and startnet.cmd are changed here.
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$workspace = Split-Path -Parent $repository
$wimlib = Join-Path $workspace 'tools\wimlib-1.14.5\wimlib-imagex.exe'
$sourceHash = '7E423FD9E6885C12E0D7C5FC70E7D0B1FEF32C4D275EE79E32CFCDA7985141E7'
$viosockHash = '1F9F268DCCD844BCFC6D4C9D4921577A32B7555D11E80AC5D95A46D818612B43'

if (Test-Path -LiteralPath $OutputWim) { throw "Refusing to overwrite: $OutputWim" }
if (Test-Path -LiteralPath $WorkDirectory) { throw "Use a new work directory: $WorkDirectory" }
if ((Get-FileHash -LiteralPath $SourceWim -Algorithm SHA256).Hash -ne $sourceHash) {
  throw 'Source is not the preserved graphics/viosock WIM.'
}
New-Item -ItemType Directory -Path $WorkDirectory | Out-Null
Copy-Item -LiteralPath $SourceWim -Destination $OutputWim
$startnet = Join-Path $WorkDirectory 'startnet.cmd'
[IO.File]::WriteAllText($startnet, 'start "" /b \WinAvf\WinAvfInput.exe' + "`r`nwpeinit`r`n", [Text.Encoding]::ASCII)
$commands = Join-Path $WorkDirectory 'wim-update.txt'
@(
  "add `"$AgentExe`" /WinAvf/WinAvfInput.exe",
  "add `"$startnet`" /Windows/System32/startnet.cmd"
) | Set-Content -LiteralPath $commands -Encoding ascii
Get-Content -LiteralPath $commands | & $wimlib update $OutputWim 2 --threads=4
if ($LASTEXITCODE -ne 0) { throw 'wimlib append update failed.' }
& $wimlib verify $OutputWim
if ($LASTEXITCODE -ne 0) { throw 'wimlib verify failed.' }
$verify = Join-Path $WorkDirectory 'verify'
New-Item -ItemType Directory -Path $verify | Out-Null
$viosockGuestPath = '\Windows\System32\DriverStore\FileRepository\viosock.inf_arm64_129d76e171859f2d\viosock.sys'
& $wimlib extract $OutputWim 2 '\WinAvf\WinAvfInput.exe' '\Windows\System32\startnet.cmd' $viosockGuestPath --dest-dir=$verify
if ($LASTEXITCODE -ne 0) { throw 'Could not extract verification files.' }
if ((Get-FileHash -LiteralPath $AgentExe -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $verify 'WinAvfInput.exe') -Algorithm SHA256).Hash) { throw 'Agent changed in WIM.' }
if ((Get-FileHash -LiteralPath (Join-Path $verify 'viosock.sys') -Algorithm SHA256).Hash -ne $viosockHash) { throw 'viosock.sys differs from signed package.' }
$expected = 'start "" /b \WinAvf\WinAvfInput.exe' + "`r`nwpeinit`r`n"
if ((Get-Content -LiteralPath (Join-Path $verify 'startnet.cmd') -Raw) -ne $expected) { throw 'Unexpected startnet.cmd.' }
[pscustomobject]@{
  Wim = (Resolve-Path -LiteralPath $OutputWim).Path
  WimBytes = (Get-Item -LiteralPath $OutputWim).Length
  WimSha256 = (Get-FileHash -LiteralPath $OutputWim -Algorithm SHA256).Hash
  AgentSha256 = (Get-FileHash -LiteralPath $AgentExe -Algorithm SHA256).Hash
  ViosockSha256 = $viosockHash
  ChangedPaths = '\WinAvf\WinAvfInput.exe; \Windows\System32\startnet.cmd'
  Result = 'PASS'
} | Format-List

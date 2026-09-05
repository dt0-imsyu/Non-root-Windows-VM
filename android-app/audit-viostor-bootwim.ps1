param(
    [Parameter(Mandatory = $true)] [string] $Wim,
    [Parameter(Mandatory = $true)] [string] $MountDirectory,
    [Parameter(Mandatory = $true)] [string] $Report
)

$ErrorActionPreference = 'Stop'
$dism = Join-Path $env:SystemRoot 'System32\dism.exe'
New-Item -ItemType Directory -Path $MountDirectory -Force | Out-Null
& $dism /Mount-Image /ImageFile:$Wim /Index:2 /MountDir:$MountDirectory /ReadOnly
try {
    $lines = & $dism /Image:$MountDirectory /Get-Drivers /Format:Table 2>&1
    $hive = 'HKLM\WinAvfViostorAudit'
    & reg.exe load $hive "$MountDirectory\Windows\System32\config\SYSTEM"
    try { $service = & reg.exe query "$hive\ControlSet001\Services\viostor" /v Start 2>&1 } finally { & reg.exe unload $hive }
    ($lines + '' + $service) | Set-Content -LiteralPath $Report -Encoding UTF8
} finally {
    & $dism /Unmount-Image /MountDir:$MountDirectory /Discard
}

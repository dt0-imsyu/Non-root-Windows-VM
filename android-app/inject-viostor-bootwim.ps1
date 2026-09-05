param(
    [Parameter(Mandatory = $true)] [string] $SourceWim,
    [Parameter(Mandatory = $true)] [string] $OutputWim,
    [Parameter(Mandatory = $true)] [string] $DriverDirectory,
    [Parameter(Mandatory = $true)] [string] $MountDirectory
)

$ErrorActionPreference = 'Stop'
$dism = Join-Path $env:SystemRoot 'System32\dism.exe'
Copy-Item -LiteralPath $SourceWim -Destination $OutputWim -Force
New-Item -ItemType Directory -Path $MountDirectory -Force | Out-Null
& $dism /Mount-Image /ImageFile:$OutputWim /Index:2 /MountDir:$MountDirectory
try {
    & $dism /Image:$MountDirectory /Add-Driver /Driver:$DriverDirectory
    if ($LASTEXITCODE -ne 0) { throw "DISM Add-Driver failed: $LASTEXITCODE" }
    & $dism /Unmount-Image /MountDir:$MountDirectory /Commit
    if ($LASTEXITCODE -ne 0) { throw "DISM Unmount-Image failed: $LASTEXITCODE" }
} catch {
    & $dism /Unmount-Image /MountDir:$MountDirectory /Discard
    throw
}

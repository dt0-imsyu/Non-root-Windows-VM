param(
    [Parameter(Mandatory = $true)] [string] $Bcd,
    [Parameter(Mandatory = $true)] [string] $Report
)

$ErrorActionPreference = 'Stop'
& "$env:SystemRoot\System32\bcdedit.exe" /store $Bcd /enum all | Set-Content -LiteralPath $Report -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw "bcdedit failed: $LASTEXITCODE" }

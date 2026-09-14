param(
    [Parameter(Mandatory = $true)] [string] $BcdPath,
    [Parameter(Mandatory = $true)] [string] $ReportPath,
    [Parameter(Mandatory = $true)] [string] $ExpectedInputSha256
)

# Must run elevated.  It changes only the supplied offline BCD copy.
$ErrorActionPreference = 'Stop'
$bcd = (Resolve-Path -LiteralPath $BcdPath).Path
$expected = $ExpectedInputSha256.ToUpperInvariant()
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $bcd).Hash
if ($actual -ne $expected) { throw "Unexpected offline BCD SHA-256: $actual" }

$bcdedit = "$env:SystemRoot\System32\bcdedit.exe"
function Invoke-Bcd([string[]] $Arguments) {
    & $bcdedit @Arguments
    if ($LASTEXITCODE -ne 0) { throw "BCDEdit failed ($LASTEXITCODE): $($Arguments -join ' ')" }
}

Invoke-Bcd @('/store', $bcd, '/set', '{default}', 'bootdebug', 'on')
Invoke-Bcd @('/store', $bcd, '/debug', '{default}', 'on')
Invoke-Bcd @('/store', $bcd, '/dbgsettings', 'serial', 'debugport:1', 'baudrate:115200')

& $bcdedit /store $bcd /enum all | Set-Content -LiteralPath $ReportPath -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw "BCDEdit audit failed ($LASTEXITCODE)" }

param(
    [Parameter(Mandatory = $true)] [string] $Bcd,
    [Parameter(Mandatory = $true)] [string] $Report
)

$ErrorActionPreference = 'Stop'
$bcdedit = "$env:SystemRoot\System32\bcdedit.exe"
& $bcdedit /store $Bcd /set '{default}' bootdebug on
if ($LASTEXITCODE -ne 0) { throw "bcdedit set bootdebug failed: $LASTEXITCODE" }
& $bcdedit /store $Bcd /enum '{default}' | Set-Content -LiteralPath $Report -Encoding UTF8

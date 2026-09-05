param(
    [Parameter(Mandatory = $true)] [string] $Bcd,
    [Parameter(Mandatory = $true)] [string] $Report
)

$ErrorActionPreference = 'Stop'
$bcdedit = "$env:SystemRoot\System32\bcdedit.exe"
& $bcdedit /store $Bcd /set '{default}' ems on
if ($LASTEXITCODE -ne 0) { throw "bcdedit set ems failed: $LASTEXITCODE" }
& $bcdedit /store $Bcd /set '{emssettings}' bootems on
if ($LASTEXITCODE -ne 0) { throw "bcdedit set bootems failed: $LASTEXITCODE" }
& $bcdedit /store $Bcd /enum '{default}' | Set-Content -LiteralPath $Report -Encoding UTF8
& $bcdedit /store $Bcd /enum '{emssettings}' | Add-Content -LiteralPath $Report -Encoding UTF8

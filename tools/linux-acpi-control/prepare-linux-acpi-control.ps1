[CmdletBinding()]
param()

# One elevated entry point for the disposable Linux ACPI control.  The child
# scripts reject existing outputs, preserve the immutable raw baseline, and do
# not communicate with Android or launch a VM.
$ErrorActionPreference = 'Stop'

$materialize = Join-Path $PSScriptRoot 'materialize-linux-acpi-control.ps1'
$audit = Join-Path $PSScriptRoot 'audit-linux-acpi-control.ps1'
foreach ($path in @($materialize, $audit)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required control script is missing: $path" }
}

& $materialize
& $audit

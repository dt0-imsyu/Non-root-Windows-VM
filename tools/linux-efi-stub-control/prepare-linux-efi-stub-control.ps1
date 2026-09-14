[CmdletBinding()]
param()

# Runs only the two offline stages, in order.  It deliberately does not build a
# patch, contact Android, or launch a VM.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
& (Join-Path $here 'materialize-linux-efi-stub-control.ps1')
& (Join-Path $here 'audit-linux-efi-stub-control.ps1')

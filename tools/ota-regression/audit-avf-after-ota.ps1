[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) ('build-logs\\ota-avf-audit-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    [string]$AdbPath = (Join-Path $env:LOCALAPPDATA 'Android\\Sdk\\platform-tools\\adb.exe')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AdbPath)) { throw "adb.exe not found: $AdbPath" }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$report = Join-Path $OutputDirectory 'avf-ota-readonly-audit.txt'

function Invoke-AdbText([string[]]$Arguments) {
    $value = & $AdbPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "adb $($Arguments -join ' ') failed: $value" }
    return ($value | Out-String).TrimEnd()
}

$devices = Invoke-AdbText @('devices', '-l')
$online = @($devices -split "`r?`n" | Where-Object { $_ -match "\sdevice(\s|$)" })
if ($online.Count -ne 1) { throw "Expected exactly one authorized device; got $($online.Count)." }

$properties = @(
    'ro.product.model',
    'ro.build.fingerprint',
    'ro.build.version.incremental',
    'ro.build.version.security_patch',
    'ro.vendor.build.security_patch',
    'ro.boot.hypervisor.version',
    'ro.boot.hypervisor.vm.supported',
    'ro.boot.hypervisor.protected_vm.supported',
    'ro.debuggable',
    'ro.boot.verifiedbootstate'
)

try {
    @(
        'scope=READ_ONLY_NO_VM_NO_MEDIA_NO_FIRMWARE_CHANGE',
        "captured_utc=$((Get-Date).ToUniversalTime().ToString('o'))",
        "device=$online"
    ) | Set-Content -LiteralPath $report -Encoding utf8

    Add-Content -LiteralPath $report -Value "`n[system-properties]"
    foreach ($name in $properties) {
        Add-Content -LiteralPath $report -Value "$name=$(Invoke-AdbText @('shell', 'getprop', $name))"
    }

    Add-Content -LiteralPath $report -Value "`n[avf]"
    Add-Content -LiteralPath $report -Value ('vm.info=' + (Invoke-AdbText @('shell', 'vm', 'info')))
    Add-Content -LiteralPath $report -Value ('vm.run.help=' + (Invoke-AdbText @('shell', 'vm', 'run', '--help')))
    foreach ($feature in 'custom_vm', 'console_input', 'paravirtualized_devices') {
        Add-Content -LiteralPath $report -Value "feature.$feature=$(Invoke-AdbText @('shell', 'vm', 'check-feature-enabled', $feature))"
    }

    Add-Content -LiteralPath $report -Value "`n[apex-and-packages]"
    Add-Content -LiteralPath $report -Value ('framework_virtualization.sha256=' + (Invoke-AdbText @('shell', 'sha256sum', '/apex/com.android.virt/javalib/framework-virtualization.jar')))
    Add-Content -LiteralPath $report -Value ('virtualization.package=' + (Invoke-AdbText @('shell', 'dumpsys', 'package', 'com.android.virtualization')))
    Add-Content -LiteralPath $report -Value ('terminal.package=' + (Invoke-AdbText @('shell', 'dumpsys', 'package', 'com.android.virtualization.terminal')))

    Add-Content -LiteralPath $report -Value "`n[result]"
    Add-Content -LiteralPath $report -Value 'RESULT=PASS'
    Add-Content -LiteralPath $report -Value 'NEXT=Compare this report with the last known AVF audit before any VM runtime.'
} catch {
    Add-Content -LiteralPath $report -Value "RESULT=FAIL`nERROR=$($_.Exception.Message)"
    throw
}

Write-Output "RESULT=PASS"
Write-Output "REPORT=$report"

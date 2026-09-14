[CmdletBinding()]
param(
    [string] $PatchPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-acpi-control-20260911\linux-acpi-control-bookworm.patch',
    [string] $ExpectedPatchSha256 = 'ACA05CE553342822DB7D727F77279E91C66CF6CBF13127642D60E03F445EE7BC',
    [string] $ArtifactDir = ('C:\Users\denis\MainProjects\win11ontab\build-logs\linux-acpi-runtime-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [string] $AdbPath = 'C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe',
    [int] $DurationSeconds = 100
)

# One bounded product-topology Linux control. It applies an already-audited
# reversible WAVFPAT1 bundle through the existing WinAVF launcher, captures the
# raw serial output, then demands exact transactional rollback. No firmware,
# BCD, WIM, Android system setting, or source image is changed.
$ErrorActionPreference = 'Stop'
if ($DurationSeconds -lt 30 -or $DurationSeconds -gt 180) { throw 'DurationSeconds must be 30..180.' }

$expectedBaseline = '2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7'
$app = 'com.example.winavf'
$image = '/sdcard/Android/data/com.example.winavf/files/win11-gop-ebs-r1.img'
$patchRemote = '/sdcard/Android/data/com.example.winavf/files/winavf-image-patch.bin'
$serialRemote = '/sdcard/Android/data/com.example.winavf/files/serial.log'
$rollbackRemote = '/sdcard/Android/data/com.example.winavf/files/rollback-report.txt'

if (-not (Test-Path -LiteralPath $AdbPath -PathType Leaf)) { throw "ADB executable not found: $AdbPath" }
$patch = (Resolve-Path -LiteralPath $PatchPath).Path
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash.ToUpperInvariant() -ne $ExpectedPatchSha256) { throw 'Local Linux-control patch SHA-256 mismatch.' }
if (Test-Path -LiteralPath $ArtifactDir) { throw "Refusing to overwrite existing artifact directory: $ArtifactDir" }
New-Item -ItemType Directory -Path $ArtifactDir | Out-Null
$status = Join-Path $ArtifactDir 'run-status.txt'

function Invoke-Adb([string[]] $Arguments, [string] $Name) {
    $stdout = Join-Path $ArtifactDir ($Name + '.stdout.txt')
    $stderr = Join-Path $ArtifactDir ($Name + '.stderr.txt')
    $process = Start-Process -FilePath $AdbPath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($process.ExitCode -ne 0) { throw "adb $Name failed with exit code $($process.ExitCode)." }
    return (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
}
function Get-RemoteHash([string] $RemotePath, [string] $Name) {
    $text = Invoke-Adb @('exec-out','sha256sum',$RemotePath) $Name
    if ($text -notmatch '^([0-9a-fA-F]{64})\s') { throw "Could not read SHA-256 for Android file: $RemotePath" }
    return $matches[1].ToUpperInvariant()
}
function Append-Status([string] $Line) { Add-Content -LiteralPath $status -Value $Line -Encoding ascii }

$started = $false
try {
    $before = Get-RemoteHash $image 'baseline-before'
    if ($before -ne $expectedBaseline) { throw "Android immutable baseline SHA-256 mismatch: $before" }
    Append-Status "BASELINE_BEFORE_SHA256=$before"
    $vmList = Invoke-Adb @('shell','vm','list') 'vm-list-before'
    if ($vmList -match 'winavf-gop-ebs-r1') { throw 'Product VM is already running; refusing a second launch.' }
    Append-Status 'VM_BEFORE=ABSENT'

    Invoke-Adb @('push',$patch,$patchRemote) 'push-patch' | Out-Null
    $staged = Get-RemoteHash $patchRemote 'patch-staged'
    if ($staged -ne $ExpectedPatchSha256) { throw "Android staged patch SHA-256 mismatch: $staged" }
    Append-Status "PATCH_STAGED_SHA256=$staged"
    Invoke-Adb @('shell','rm','-f',$serialRemote,$rollbackRemote) 'clear-old-observables' | Out-Null
    # An existing task can be merely brought to the foreground by `am start`,
    # bypassing a fresh intent delivery. The product KD runner already proves
    # that stopping this one app before a diagnostic launch is safe and does
    # not affect Android services or the immutable source image.
    Invoke-Adb @('shell','am','force-stop',$app) 'force-stop-before-launch' | Out-Null
    Start-Sleep -Seconds 2
    Append-Status 'APP_FORCE_STOP_BEFORE_LAUNCH=PASS'

    Invoke-Adb @('shell','am','start','-n', "$app/.MainActivity", '--ez','start','true') 'start-vm' | Out-Null
    $started = $true
    Append-Status "VM_STARTED_UTC=$([DateTime]::UtcNow.ToString('O'))"
    Start-Sleep -Seconds $DurationSeconds
    Append-Status "CAPTURE_WINDOW_SECONDS=$DurationSeconds"
}
finally {
    if ($started) {
        try { Invoke-Adb @('shell','am','force-stop',$app) 'force-stop-vm' | Out-Null; Append-Status 'APP_FORCE_STOP=REQUESTED' } catch { Append-Status "APP_FORCE_STOP_ERROR=$($_.Exception.Message)" }
        Start-Sleep -Seconds 3
        try { Invoke-Adb @('shell','vm','list') 'vm-list-after-stop' | Out-Null; Append-Status 'VM_STOP_AUDIT=CAPTURED' } catch { Append-Status "VM_STOP_AUDIT_ERROR=$($_.Exception.Message)" }
        try { Invoke-Adb @('pull',$serialRemote,(Join-Path $ArtifactDir 'raw-serial.log')) 'pull-serial' | Out-Null; Append-Status 'RAW_SERIAL=PULLED' } catch { Append-Status "RAW_SERIAL_PULL_ERROR=$($_.Exception.Message)" }
        try {
            Invoke-Adb @('shell','am','start','-n', "$app/.MainActivity", '--ez','rollback','true') 'request-rollback' | Out-Null
            $deadline = [DateTime]::UtcNow.AddSeconds(75)
            $rollback = ''
            while ([DateTime]::UtcNow -lt $deadline) {
                try { $rollback = Invoke-Adb @('shell','cat',$rollbackRemote) 'read-rollback'; if ($rollback -match 'RESULT=(PASS|FAIL)') { break } } catch { }
                Start-Sleep -Seconds 2
            }
            Set-Content -LiteralPath (Join-Path $ArtifactDir 'rollback-report.txt') -Value $rollback -Encoding ascii
            if ($rollback -notmatch 'RESULT=PASS' -or $rollback -notmatch "BASELINE_SHA256=$expectedBaseline") { throw 'Launcher rollback did not report exact baseline restoration.' }
            $after = Get-RemoteHash $image 'baseline-after'
            if ($after -ne $expectedBaseline) { throw "Android baseline SHA-256 mismatch after rollback: $after" }
            Append-Status "ROLLBACK_BASELINE_SHA256=$after"
        }
        catch { Append-Status "ROLLBACK_ERROR=$($_.Exception.Message)" }
    }
}

Write-Host "ARTIFACT_DIR=$ArtifactDir"
Get-Content -LiteralPath $status

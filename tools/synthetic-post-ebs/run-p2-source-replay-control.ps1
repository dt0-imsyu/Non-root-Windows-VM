[CmdletBinding()]
param(
    [string] $PatchPath = 'C:\Users\denis\MainProjects\win11ontab\build-logs\synthetic-post-ebs-p2-source-replay-control-20260912\post-ebs-p2-source-replay-firmware.patch',
    [string] $ExpectedPatchSha256 = 'A4F54713D7A1E0698B02E0F45F7A3E3E466D78DA96688D5E08D677D4570D4BA1',
    [string] $ArtifactDir = ('C:\Users\denis\MainProjects\win11ontab\build-logs\synthetic-post-ebs-p2-source-replay-runtime-' + (Get-Date -Format 'yyyyMMdd-HHmmss')),
    [string] $AdbPath = 'C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe',
    [int] $DurationSeconds = 60
)

# One P2 source-replay control only.  It changes no Windows content, BCD,
# Android code, ACPI table, or VM topology.  The launcher verifies the exact
# baseline before applying the patch; this runner also verifies it after its
# mandatory transactional rollback.
$ErrorActionPreference = 'Stop'
if ($DurationSeconds -lt 30 -or $DurationSeconds -gt 120) { throw 'DurationSeconds must be 30..120.' }

$baseline = '2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7'
$app = 'com.example.winavf'
$image = '/sdcard/Android/data/com.example.winavf/files/win11-gop-ebs-r1.img'
$remotePatch = '/sdcard/Android/data/com.example.winavf/files/winavf-image-patch.bin'
$remoteSerial = '/sdcard/Android/data/com.example.winavf/files/serial.log'
$remoteRollback = '/sdcard/Android/data/com.example.winavf/files/rollback-report.txt'

if (-not (Test-Path -LiteralPath $AdbPath -PathType Leaf)) { throw "ADB executable not found: $AdbPath" }
$patch = (Resolve-Path -LiteralPath $PatchPath).Path
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash.ToUpperInvariant() -ne $ExpectedPatchSha256) { throw 'Local P2 replay patch SHA-256 mismatch.' }
if (Test-Path -LiteralPath $ArtifactDir) { throw "Refusing to overwrite artifact directory: $ArtifactDir" }
New-Item -ItemType Directory -Path $ArtifactDir | Out-Null
$statusPath = Join-Path $ArtifactDir 'run-status.txt'

function Add-Status([string] $line) { Add-Content -LiteralPath $statusPath -Value $line -Encoding ascii }
function Invoke-Adb([string[]] $Arguments, [string] $name) {
    $stdout = Join-Path $ArtifactDir "$name.stdout.txt"
    $stderr = Join-Path $ArtifactDir "$name.stderr.txt"
    $p = Start-Process -FilePath $AdbPath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($p.ExitCode -ne 0) { throw "adb $name failed with exit code $($p.ExitCode)." }
    Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
}
function Remote-Hash([string] $path, [string] $name) {
    $text = Invoke-Adb @('exec-out','sha256sum',$path) $name
    if ($text -notmatch '^([0-9a-fA-F]{64})\s') { throw "Could not hash Android file: $path" }
    $matches[1].ToUpperInvariant()
}

$started = $false
try {
    $before = Remote-Hash $image 'baseline-before'
    if ($before -ne $baseline) { throw "Immutable baseline SHA-256 mismatch: $before" }
    Add-Status "BASELINE_BEFORE_SHA256=$before"
    $vms = Invoke-Adb @('shell','vm','list') 'vm-list-before'
    if ($vms -match 'winavf-gop-ebs-r1') { throw 'Product VM is already running; refusing a second launch.' }
    Add-Status 'VM_BEFORE=ABSENT'

    Invoke-Adb @('push',$patch,$remotePatch) 'push-patch' | Out-Null
    $staged = Remote-Hash $remotePatch 'patch-staged'
    if ($staged -ne $ExpectedPatchSha256) { throw "Staged patch SHA-256 mismatch: $staged" }
    Add-Status "PATCH_STAGED_SHA256=$staged"
    Invoke-Adb @('shell','rm','-f',$remoteSerial,$remoteRollback) 'clear-observables' | Out-Null
    Invoke-Adb @('shell','am','force-stop',$app) 'force-stop-before-launch' | Out-Null
    Start-Sleep -Seconds 2
    Invoke-Adb @('shell','am','start','-n',"$app/.MainActivity",'--ez','start','true') 'start-vm' | Out-Null
    $started = $true
    Add-Status "VM_STARTED_UTC=$([DateTime]::UtcNow.ToString('O'))"
    Start-Sleep -Seconds $DurationSeconds
    Add-Status "CAPTURE_WINDOW_SECONDS=$DurationSeconds"
}
finally {
    if ($started) {
        try { Invoke-Adb @('shell','am','force-stop',$app) 'force-stop-vm' | Out-Null; Add-Status 'APP_FORCE_STOP=REQUESTED' } catch { Add-Status "APP_FORCE_STOP_ERROR=$($_.Exception.Message)" }
        Start-Sleep -Seconds 3
        try { Invoke-Adb @('pull',$remoteSerial,(Join-Path $ArtifactDir 'raw-serial.log')) 'pull-serial' | Out-Null; Add-Status 'RAW_SERIAL=PULLED' } catch { Add-Status "RAW_SERIAL_PULL_ERROR=$($_.Exception.Message)" }
        try {
            Invoke-Adb @('shell','am','start','-n',"$app/.MainActivity",'--ez','rollback','true') 'request-rollback' | Out-Null
            $deadline = [DateTime]::UtcNow.AddSeconds(75); $report = ''
            while ([DateTime]::UtcNow -lt $deadline) {
                try { $report = Invoke-Adb @('shell','cat',$remoteRollback) 'read-rollback'; if ($report -match 'RESULT=(PASS|FAIL)') { break } } catch { }
                Start-Sleep -Seconds 2
            }
            Set-Content -LiteralPath (Join-Path $ArtifactDir 'rollback-report.txt') -Value $report -Encoding ascii
            if ($report -notmatch 'RESULT=PASS' -or $report -notmatch "BASELINE_SHA256=$baseline") { throw 'Launcher did not report an exact rollback.' }
            $after = Remote-Hash $image 'baseline-after'
            if ($after -ne $baseline) { throw "Baseline SHA-256 mismatch after rollback: $after" }
            Add-Status "ROLLBACK_BASELINE_SHA256=$after"
        } catch { Add-Status "ROLLBACK_ERROR=$($_.Exception.Message)" }
    }
}

Write-Host "ARTIFACT_DIR=$ArtifactDir"
Get-Content -LiteralPath $statusPath

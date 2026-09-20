$ErrorActionPreference = 'Stop'
$main = Join-Path $PSScriptRoot 'complete-ubuntu-gnome-v2.ps1'
$transcript = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-gnome-20260919\complete-v2-transcript.log'
try { & $main *>&1 | Tee-Object -FilePath $transcript; exit $LASTEXITCODE }
catch { ($_ | Out-String) | Tee-Object -FilePath $transcript -Append; exit 1 }

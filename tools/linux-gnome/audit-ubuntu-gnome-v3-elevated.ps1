$ErrorActionPreference = 'Stop'
$main = Join-Path $PSScriptRoot 'audit-ubuntu-gnome-candidate.ps1'
$transcript = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-gnome-20260919\audit-v3-transcript.log'
try {
  & $main -VhdPath 'D:\winavf-ubuntu-gnome-24.04.5-v2-work-fixed.vhd' -RawPath 'E:\winavf-ubuntu-gnome-24.04.5-v3-candidate.img' -ReportPath 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-gnome-20260919\audit-v3-report.txt' *>&1 |
    Tee-Object -FilePath $transcript
  exit $LASTEXITCODE
} catch { ($_ | Out-String) | Tee-Object -FilePath $transcript -Append; exit 1 }

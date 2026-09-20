$ErrorActionPreference='Stop'
$main=Join-Path $PSScriptRoot 'fix-casper-root-v3.ps1'
$transcript='C:\Users\denis\MainProjects\win11ontab\build-logs\linux-gnome-20260919\casper-root-v3-transcript.log'
try{& $main *>&1 | Tee-Object -FilePath $transcript;exit $LASTEXITCODE}catch{($_|Out-String)|Tee-Object -FilePath $transcript -Append;exit 1}

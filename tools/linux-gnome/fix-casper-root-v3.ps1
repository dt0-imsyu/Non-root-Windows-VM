$ErrorActionPreference = 'Stop'
$vhd = 'D:\winavf-ubuntu-gnome-24.04.5-v2-work-fixed.vhd'
$raw = 'E:\winavf-ubuntu-gnome-24.04.5-v3-candidate.img'
$report = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-gnome-20260919\casper-root-v3-report.txt'
$bytes=[int64]9126805504;$offset=[int64]1048576;$partBytes=[int64]9125740032
function Hash([string]$p){(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToUpperInvariant()}
function Assert-Admin{$p=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent());if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run elevated.'}}
function Export-Raw([string]$source,[string]$destination){$i=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite);$o=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$b=[byte[]]::new(8MB);[int64]$n=0;while($n -lt $bytes){$want=[int][Math]::Min([int64]$b.Length,$bytes-$n);$got=$i.Read($b,0,$want);if($got -le 0){throw 'Unexpected VHD EOF.'};$o.Write($b,0,$got);$n+=$got};$o.Flush($true)}finally{$o.Dispose();$i.Dispose()}}
Assert-Admin
foreach($p in @($vhd)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing VHD: $p"}}
foreach($p in @($raw,$report)){if(Test-Path -LiteralPath $p){throw "Refusing to overwrite: $p"}}
$mounted=$false
try {
  Mount-DiskImage -ImagePath $vhd -NoDriveLetter;$mounted=$true
  $disk=Get-DiskImage -ImagePath $vhd|Get-Disk;if($disk.Size -ne $bytes){throw 'VHD size mismatch.'}
  $part=Get-Partition -DiskNumber $disk.Number|Where-Object {$_.Offset -eq $offset -and $_.Size -eq $partBytes};if(@($part).Count -ne 1){throw 'VHD partition geometry mismatch.'}
  $vol=$part|Get-Volume;if($vol.FileSystem -ne 'FAT32'){throw 'Expected FAT32.'};if(-not $vol.DriveLetter){Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AssignDriveLetter;$vol=Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber|Get-Volume};if(-not $vol.DriveLetter){throw 'No VHD letter.'}
  $root="$($vol.DriveLetter):";$source=Join-Path $root 'UBUNTU\CASPER';$dest=Join-Path $root 'CASPER'
  foreach($p in @($source,(Join-Path $source 'VMLINUZ'),(Join-Path $source 'INITRD'),(Join-Path $source 'MINIMAL.SQUASHFS'),(Join-Path $source 'MINIMAL.STANDARD.LIVE.SQUASHFS'),(Join-Path $source 'MINIMAL.STANDARD.SQUASHFS'))){if(-not(Test-Path -LiteralPath $p)){throw "Missing v2 casper payload: $p"}}
  if(Test-Path -LiteralPath $dest){throw 'Root casper directory already exists.'}
  Move-Item -LiteralPath $source -Destination $dest
  $emptyParent=Join-Path $root 'UBUNTU';if(Test-Path -LiteralPath $emptyParent){Remove-Item -LiteralPath $emptyParent -Force}
  foreach($p in @((Join-Path $dest 'VMLINUZ'),(Join-Path $dest 'INITRD'),(Join-Path $dest 'MINIMAL.SQUASHFS'),(Join-Path $dest 'MINIMAL.STANDARD.LIVE.SQUASHFS'),(Join-Path $dest 'MINIMAL.STANDARD.SQUASHFS'),(Join-Path $dest 'SHA256SUMS'))){if(-not(Test-Path -LiteralPath $p)){throw "Root casper move verification failed: $p"}}
  Dismount-DiskImage -ImagePath $vhd;$mounted=$false;Mount-DiskImage -ImagePath $vhd -NoDriveLetter;$mounted=$true
  $disk=Get-DiskImage -ImagePath $vhd|Get-Disk;Export-Raw ("\\.\PhysicalDrive$($disk.Number)") $raw
  @('RESULT=PASS','CHANGE=Moved only \UBUNTU\CASPER to required \CASPER',"VHD_PATH=$vhd", "RAW_PATH=$raw", "RAW_BYTES=$((Get-Item $raw).Length)", "RAW_SHA256=$(Hash $raw)", 'NEXT=Run offline audit then replace only the disposable Android GNOME medium.')|Set-Content -LiteralPath $report -Encoding utf8
  Get-Content $report
}finally{if($mounted){Dismount-DiskImage -ImagePath $vhd -ErrorAction SilentlyContinue}}

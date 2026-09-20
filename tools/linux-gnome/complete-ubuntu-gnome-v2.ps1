[CmdletBinding()]
param()

# Resume only the disposable v2 VHD after its FAT32 label was rejected.  The
# first phase already copied the immutable baseline and cleared the Windows
# payload from that temporary VHD.  This phase verifies that state, then copies
# Ubuntu files with the standard Windows FAT32 driver and exports raw sectors.
$ErrorActionPreference = 'Stop'
$baseline = 'E:\winavf-a3-append-only-runtime.img'
$vhd = 'D:\winavf-ubuntu-gnome-24.04.5-v2-work-fixed.vhd'
$iso = 'E:\winavf-linux-gnome-20260919\ubuntu-24.04.5-desktop-arm64.iso'
$launcher = 'C:\Users\denis\MainProjects\win11ontab\firmware-work\edk2\Build\ArmVirtKvmTool-AARCH64\DEBUG_GCC5\AARCH64\ArmPkg\Application\AvfUbuntuEfiStubProbe\AvfUbuntuEfiStubProbe\DEBUG\AvfUbuntuEfiStubProbe.efi'
$raw = 'E:\winavf-ubuntu-gnome-24.04.5-v2-candidate.img'
$report = 'C:\Users\denis\MainProjects\win11ontab\build-logs\linux-gnome-20260919\materialize-v2-report.txt'
$expectedBaseline = '2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7'
$expectedIso = '2BE09CA883921BFF6D8E6B0BFBAFD13E32436553B7086F33BCE3A4C5BAD8BD14'
$expectedLauncher = '21D1E844E6C3C1EB3797EC08551F6DEA6461F60663147C6566AF768DD27824B5'
$bytes = [int64]9126805504; $offset = [int64]1048576; $partitionBytes = [int64]9125740032
function Hash([string] $p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToUpperInvariant() }
function Assert-Admin {
  $p=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
  if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run elevated.'}
}
function Export-Raw([string]$source,[string]$destination){
  $i=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  $o=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try {$b=[byte[]]::new(8MB);[int64]$n=0;while($n -lt $bytes){$want=[int][Math]::Min([int64]$b.Length,$bytes-$n);$got=$i.Read($b,0,$want);if($got -le 0){throw 'Unexpected VHD EOF.'};$o.Write($b,0,$got);$n+=$got};$o.Flush($true)} finally {$o.Dispose();$i.Dispose()}
}

Assert-Admin
foreach($p in @($baseline,$vhd,$iso,$launcher)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing required file: $p"}}
if((Hash $baseline) -ne $expectedBaseline){throw 'Immutable baseline SHA mismatch.'}
if((Hash $iso) -ne $expectedIso){throw 'Official Ubuntu ISO SHA mismatch.'}
if((Hash $launcher) -ne $expectedLauncher){throw 'EFI launcher SHA mismatch.'}
foreach($p in @($raw,$report)){if(Test-Path -LiteralPath $p){throw "Refusing to overwrite: $p"}}
$vhdMounted=$false;$isoMounted=$false
try {
  Mount-DiskImage -ImagePath $vhd -NoDriveLetter; $vhdMounted=$true
  $disk=Get-DiskImage -ImagePath $vhd|Get-Disk
  if($disk.Size -ne $bytes){throw 'Temporary VHD geometry mismatch.'}
  $part=Get-Partition -DiskNumber $disk.Number|Where-Object {$_.Offset -eq $offset -and $_.Size -eq $partitionBytes}
  if(@($part).Count -ne 1){throw 'Expected FAT32 partition missing.'}
  $vol=$part|Get-Volume;if($vol.FileSystem -ne 'FAT32'){throw 'Temporary VHD is not FAT32.'}
  if(-not $vol.DriveLetter){Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AssignDriveLetter;$vol=Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber|Get-Volume}
  if(-not $vol.DriveLetter){throw 'No drive letter for temporary VHD.'}
  $root="$($vol.DriveLetter):"
  foreach($gone in @('EFI\MICROSOFT','SOURCES')){if(Test-Path -LiteralPath (Join-Path $root $gone)){throw "Expected cleared Windows payload remains: $gone"}}
  New-Item -ItemType Directory -Force -Path (Join-Path $root 'EFI\BOOT'),(Join-Path $root 'UBUNTU\CASPER'),(Join-Path $root '.disk')|Out-Null
  Mount-DiskImage -ImagePath $iso -Access ReadOnly -NoDriveLetter;$isoMounted=$true
  $src=(Get-Volume|Where-Object {$_.FileSystem -eq 'CDFS' -and $_.FileSystemLabel -eq 'Ubuntu 24.04.5 L'}|Select-Object -First 1).Path
  if(-not $src){throw 'Ubuntu CDFS source not found.'}
  Get-ChildItem -LiteralPath (Join-Path $src 'casper') -Force|Copy-Item -Destination (Join-Path $root 'UBUNTU\CASPER') -Recurse -Force
  Get-ChildItem -LiteralPath (Join-Path $src '.disk') -Force|Copy-Item -Destination (Join-Path $root '.disk') -Recurse -Force
  Copy-Item -LiteralPath $launcher -Destination (Join-Path $root 'EFI\BOOT\BOOTAA64.EFI') -Force
  Dismount-DiskImage -ImagePath $iso;$isoMounted=$false
  Dismount-DiskImage -ImagePath $vhd;$vhdMounted=$false
  Mount-DiskImage -ImagePath $vhd -NoDriveLetter;$vhdMounted=$true
  $disk=Get-DiskImage -ImagePath $vhd|Get-Disk;$part=Get-Partition -DiskNumber $disk.Number|Where-Object {$_.Offset -eq $offset -and $_.Size -eq $partitionBytes}
  if(@($part).Count -ne 1){throw 'VHD GPT geometry changed across flush.'}
  Export-Raw ("\\.\PhysicalDrive$($disk.Number)") $raw
  @('RESULT=PASS',"BASELINE_SHA256=$expectedBaseline", "UBUNTU_ISO_SHA256=$expectedIso", "LAUNCHER_SHA256=$expectedLauncher", "VHD_PATH=$vhd", "RAW_PATH=$raw", "RAW_BYTES=$((Get-Item $raw).Length)", "RAW_SHA256=$(Hash $raw)", 'PAYLOAD=Ubuntu Desktop casper layers copied via Windows FAT32 driver', 'NEXT=Run read-only audit before Android staging.')|Set-Content -LiteralPath $report -Encoding utf8
  Get-Content -LiteralPath $report
} finally {if($isoMounted){Dismount-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue};if($vhdMounted){Dismount-DiskImage -ImagePath $vhd -ErrorAction SilentlyContinue}}

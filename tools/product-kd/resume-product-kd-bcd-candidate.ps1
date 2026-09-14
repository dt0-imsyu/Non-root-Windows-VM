<#
Recovery for the one interrupted materialization attempt only.

It reuses exactly D:\winavf-product-kd-bcd-work-fixed.vhd, which was fully
created from the SHA-verified baseline before the prior failure.  It does not
delete the retained VHD or its incomplete raw output.  Instead it writes a new
candidate name after verifying the VHD geometry and BCD read-back.
#>
[CmdletBinding()]
param(
  [string] $VhdPath = 'D:\winavf-product-kd-bcd-work-fixed.vhd',
  [string] $BcdCandidate = 'C:\Users\denis\MainProjects\win11ontab\Non-root-Windows-VM\build-logs\shell-windows-kd-bootmgr-runtime-20260907\mtools\BCD.source-current',
  [string] $OutputRaw = 'E:\winavf-product-kd-bcd-candidate-20260909-r2.img',
  [string] $ReportPath = 'C:\Users\denis\MainProjects\win11ontab\Non-root-Windows-VM\build-logs\product-kd-preflight-20260909\resume-product-kd-bcd-candidate.report.txt'
)

$ErrorActionPreference = 'Stop'
$expectedBcd = 'DE6698BF9CCF5205403A5E8ED1D6CC5E2790A3E3EF23F4539B512D1C0DFB9A11'
$expectedBytes = 9126805504L
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script from an elevated PowerShell window.' }
if (-not (Test-Path -LiteralPath $VhdPath)) { throw "Expected retained VHD is missing: $VhdPath" }
if (Test-Path -LiteralPath $OutputRaw) { throw "Refusing to overwrite new candidate path: $OutputRaw" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $BcdCandidate).Hash -ne $expectedBcd) { throw 'KD BCD candidate SHA-256 mismatch.' }

$mountedHere = $false
try {
  $image = Get-DiskImage -ImagePath $VhdPath
  if (-not $image.Attached) { Mount-DiskImage -ImagePath $VhdPath -NoDriveLetter; $mountedHere = $true; $image = Get-DiskImage -ImagePath $VhdPath }
  $disk = $image | Get-Disk
  if ($disk.Size -ne $expectedBytes) { throw "Unexpected VHD virtual disk size: $($disk.Size)" }
  $part = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Offset -eq 1048576 -and $_.Size -eq 9125740032 }
  if (@($part).Count -ne 1) { throw 'Expected temporary FAT32 partition was not found.' }
  $volume = $part | Get-Volume
  if ($volume.FileSystem -ne 'FAT32') { throw "Expected FAT32, found: $($volume.FileSystem)" }
  if (-not $volume.DriveLetter) {
    Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber -AssignDriveLetter
    $volume = Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber | Get-Volume
  }
  if (-not $volume.DriveLetter) { throw 'Temporary VHD partition has no usable drive letter.' }
  $targetBcd = "$($volume.DriveLetter):\EFI\Microsoft\Boot\BCD"
  if (-not (Test-Path -LiteralPath $targetBcd)) { throw "BCD is missing: $targetBcd" }
  Copy-Item -LiteralPath $BcdCandidate -Destination $targetBcd -Force
  $readBack = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetBcd).Hash
  if ($readBack -ne $expectedBcd) { throw "Windows FAT BCD read-back mismatch: $readBack" }

  $source = [IO.File]::Open("\\.\PhysicalDrive$($disk.Number)", [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
  $target = [IO.File]::Open($OutputRaw, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try {
    $buffer = New-Object byte[] (8MB); [int64] $copied = 0
    while ($copied -lt $expectedBytes) {
      $want = [int][Math]::Min([int64]$buffer.Length, $expectedBytes - $copied)
      $read = $source.Read($buffer, 0, $want)
      if ($read -le 0) { throw 'Unexpected VHD raw EOF.' }
      $target.Write($buffer, 0, $read); $copied += $read
    }
    $target.Flush($true)
  } finally { $target.Dispose(); $source.Dispose() }
  if ((Get-Item -LiteralPath $OutputRaw).Length -ne $expectedBytes) { throw 'Raw candidate length mismatch.' }
  [pscustomobject]@{ Result='PASS'; Vhd=$VhdPath; DiskNumber=$disk.Number; DriveLetter=$volume.DriveLetter; BcdSha256=$readBack; Candidate=$OutputRaw; CandidateBytes=(Get-Item -LiteralPath $OutputRaw).Length } | Format-List | Set-Content -LiteralPath $ReportPath -Encoding UTF8
  Get-Content -LiteralPath $ReportPath
} finally {
  if ($mountedHere -or (Get-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue).Attached) { Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue }
}

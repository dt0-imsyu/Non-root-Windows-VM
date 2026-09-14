[CmdletBinding()]
param(
  [string] $EfiPath = 'C:\Users\denis\MainProjects\win11ontab\firmware-work\edk2\Build\ArmVirtKvmTool-AARCH64\DEBUG_GCC5\AARCH64\ArmPkg\Application\QemuContractProbe\QemuContractProbe\DEBUG\QemuContractProbe.efi',
  [string] $VhdPath = 'D:\qemu-contract-probe-20260913.vhd'
)

$ErrorActionPreference = 'Stop'

$efi = (Resolve-Path -LiteralPath $EfiPath).Path
if (Test-Path -LiteralPath $VhdPath) { throw "Refusing to overwrite: $VhdPath" }

$diskpart = Join-Path $PSScriptRoot 'create-qemu-contract-vhd.diskpart'
$useHyperV = $null -ne (Get-Command New-VHD -ErrorAction SilentlyContinue)
$vhd = $null
$drive = $null
try {
  if ($useHyperV) {
    $vhd = New-VHD -Path $VhdPath -Fixed -SizeBytes 128MB
    $disk = Mount-VHD -Path $vhd.Path -PassThru | Get-Disk
  } else {
    if ($VhdPath -ne 'D:\qemu-contract-probe-20260913.vhd') { throw 'DiskPart fallback supports only the default temporary VHD path.' }
    if (Get-Volume -DriveLetter Q -ErrorAction SilentlyContinue) { throw 'Drive letter Q: is occupied; do not run the fixed DiskPart fallback.' }
    & diskpart.exe /s $diskpart
    if ($LASTEXITCODE -ne 0) { throw 'DiskPart could not create the temporary VHD.' }
    $disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
  }
  if ($disk.Size -ne 134217728) { throw 'Unexpected temporary VHD geometry.' }
  if ($useHyperV) {
    $disk | Initialize-Disk -PartitionStyle GPT
    $part = $disk | New-Partition -GptType '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}' -UseMaximumSize -AssignDriveLetter
    $vol = $part | Format-Volume -FileSystem FAT32 -NewFileSystemLabel QCP -Confirm:$false
  } else {
    $part = $disk | Get-Partition | Where-Object DriveLetter -eq 'Q'
    $vol = $part | Get-Volume
  }
  $drive = "$($vol.DriveLetter):"
  New-Item -ItemType Directory -Path "$drive\EFI\BOOT" -Force | Out-Null
  Copy-Item -LiteralPath $efi -Destination "$drive\EFI\BOOT\BOOTAA64.EFI" -Force
  $copied = Get-FileHash -LiteralPath "$drive\EFI\BOOT\BOOTAA64.EFI" -Algorithm SHA256
  $source = Get-FileHash -LiteralPath $efi -Algorithm SHA256
  if ($copied.Hash -ne $source.Hash) { throw 'EFI copy hash mismatch.' }
  $check = chkdsk $drive 2>&1
  if ($LASTEXITCODE -ne 0) { throw "CHKDSK failed: $check" }
}
finally {
  Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue
}

$hash = Get-FileHash -LiteralPath $VhdPath -Algorithm SHA256
[pscustomobject]@{
  RESULT = 'PASS'
  VHD_PATH = $VhdPath
  VHD_BYTES = (Get-Item -LiteralPath $VhdPath).Length
  VHD_SHA256 = $hash.Hash
  EFI_SHA256 = (Get-FileHash -LiteralPath $efi -Algorithm SHA256).Hash
  LAYOUT = 'GPT + FAT32 ESP + EFI/BOOT/BOOTAA64.EFI'
}

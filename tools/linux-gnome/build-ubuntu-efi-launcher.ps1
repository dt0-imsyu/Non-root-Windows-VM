[CmdletBinding()]
param()

# Builds only the disposable Ubuntu EFI-stub launcher.  It uses the preserved
# r4 Windows/MSYS tool environment but does not build, deploy, or patch a
# KVMTOOL firmware FD.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$workspace = Join-Path $repo 'firmware-work\edk2'
$baseTools = Join-Path $workspace 'BaseTools'
$win64 = Join-Path $baseTools 'Bin\Win64'
$win32 = Join-Path $baseTools 'Bin\Win32'
$python = Join-Path $repo 'tools\toolchains\llvm-mingw-20260826-clean-extract\llvm-mingw-20260826-ucrt-x86_64\python\bin\python.exe'
$gccPrefix = Join-Path $repo 'tools\arm-gnu-toolchain-15.2\bin\aarch64-none-elf-'
$gccBin = Split-Path -Parent $gccPrefix
$makeBin = 'C:\msys64\mingw64\bin'
$buildPy = Join-Path $baseTools 'Source\Python\build\build.py'
$module = 'ArmPkg\Application\AvfUbuntuEfiStubProbe\AvfUbuntuEfiStubProbe.inf'
$efi = Join-Path $workspace 'Build\ArmVirtKvmTool-AARCH64\DEBUG_GCC5\AARCH64\ArmPkg\Application\AvfUbuntuEfiStubProbe\AvfUbuntuEfiStubProbe\DEBUG\AvfUbuntuEfiStubProbe.efi'
$logDir = Join-Path $repo 'build-logs\linux-gnome-20260919'
$log = Join-Path $logDir ('build-ubuntu-efi-launcher-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')

foreach ($path in @($workspace, $win64, $win32, $python, ($gccPrefix + 'gcc.exe'), (Join-Path $makeBin 'mingw32-make.exe'), $buildPy)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing preserved build component: $path" }
}
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$env:WORKSPACE = $workspace
$env:EDK_TOOLS_PATH = $baseTools
$env:EDK_TOOLS_BIN = $win64
$env:CONF_PATH = Join-Path $workspace 'Conf'
$env:PYTHON_COMMAND = $python
$env:PYTHONPATH = Join-Path $baseTools 'Source\Python'
$env:GCC5_AARCH64_PREFIX = $gccPrefix
$env:GCC_HOST_BIN = (Join-Path $makeBin 'mingw32-')
$env:MAKE_FLAGS = ''
$env:SHELL = 'C:\Windows\System32\cmd.exe'
$env:MAKESHELL = 'C:\Windows\System32\cmd.exe'
$env:MSYS_NO_PATHCONV = '1'
$env:MSYS2_ARG_CONV_EXCL = '*'
$env:PATH = @('C:\Windows\System32', 'C:\Windows', $win64, $win32, $gccBin, $makeBin) -join ';'

$started = Get-Date
$before = if (Test-Path -LiteralPath $efi) { Get-Item -LiteralPath $efi } else { $null }
Push-Location $workspace
try {
  & $python $buildPy -n 4 -a AARCH64 -t GCC5 -p 'ArmVirtPkg\ArmVirtKvmTool.dsc' -b DEBUG -m $module 2>&1 |
    Tee-Object -FilePath $log
  $exitCode = $LASTEXITCODE
}
finally { Pop-Location }

$after = if (Test-Path -LiteralPath $efi) { Get-Item -LiteralPath $efi } else { $null }
if ($exitCode -ne 0 -or $null -eq $after -or ($null -ne $before -and $after.LastWriteTime -le $started)) {
  throw "UBUNTU_EFI_LAUNCHER_BUILD=FAIL exit=$exitCode log=$log"
}

[pscustomobject]@{
  UBUNTU_EFI_LAUNCHER_BUILD = 'PASS'
  Efi = $efi
  Bytes = $after.Length
  Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $efi).Hash
  Log = $log
} | Format-List

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workspaceRoot = Split-Path -Parent $repo
$edk2 = Join-Path $workspaceRoot 'firmware-work\edk2'
$tools = Join-Path $edk2 'BaseTools'
$toolsBin = Join-Path $tools 'Source\C\bin'
$python = 'C:\Users\denis\AppData\Local\Programs\Python\Python314\python.exe'
$buildPy = Join-Path $tools 'Source\Python\build\build.py'
$gccPrefix = Join-Path $workspaceRoot 'tools\arm-gnu-toolchain-15.2\bin\aarch64-none-elf-'
$gccBin = Split-Path -Parent $gccPrefix
$mingwBin = 'C:\msys64\mingw64\bin'
$iaslBin = Join-Path $workspaceRoot 'firmware-work\acpica\generate\unix\bin'
$runtimeBin = Join-Path $workspaceRoot 'tools\msys-runtime'
$module = 'ArmPkg\Application\QemuContractProbe\QemuContractProbe.inf'
$platform = 'ArmVirtPkg\ArmVirtQemu.dsc'
$output = Join-Path $edk2 'Build\ArmVirtQemu-AARCH64\DEBUG_GCC5\AARCH64\ArmPkg\Application\QemuContractProbe\QemuContractProbe\DEBUG\QemuContractProbe.efi'
$logDir = Join-Path $workspaceRoot 'build-logs\qemu-contract-20260913'
$log = Join-Path $logDir 'build-qemu-contract-probe.log'

foreach ($path in @($edk2, $toolsBin, $python, $buildPy, ($gccBin + '\aarch64-none-elf-gcc.exe'), ($mingwBin + '\mingw32-make.exe'), ($iaslBin + '\iasl'))) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing build input: $path" }
}
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$env:WORKSPACE = $edk2
$env:EDK_TOOLS_PATH = $tools
$env:BASE_TOOLS_PATH = $tools
$env:PYTHONPATH = Join-Path $tools 'Source\Python'
$env:WORKSPACE_TOOLS_PATH = $tools
$env:EDK_TOOLS_BIN = $toolsBin
$env:CONF_PATH = Join-Path $edk2 'Conf'
$env:PYTHON_COMMAND = $python
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$env:GCC5_AARCH64_PREFIX = $gccPrefix
$env:GCC_HOST_PREFIX = 'C:\msys64\mingw64\bin\mingw32-'
$env:GCC_HOST_BIN = $env:GCC_HOST_PREFIX
$env:IASL_PREFIX = $iaslBin + '\'
$env:PATH = @('C:\Windows\System32','C:\Windows',(Join-Path $tools 'BinWrappers\WindowsLike'),$toolsBin,$gccBin,$mingwBin,$iaslBin,$runtimeBin) -join ';'
$env:MSYS_NO_PATHCONV = '1'
$env:MSYS2_ARG_CONV_EXCL = '*'
$env:SHELL = 'C:\Windows\System32\cmd.exe'
$env:MAKESHELL = 'C:\Windows\System32\cmd.exe'

Push-Location $edk2
try {
    "Command: build platform $platform module $module" | Set-Content -LiteralPath $log -Encoding utf8
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $python $buildPy -n 4 -a AARCH64 -t GCC5 -p $platform -b DEBUG -m $module 2>&1 | Tee-Object -FilePath $log -Append
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $saved }
} finally { Pop-Location }

if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $output)) {
    throw "QEMU_CONTRACT_PROBE_BUILD=BLOCKED; exit=$exitCode log=$log"
}

$item = Get-Item -LiteralPath $output
[pscustomobject]@{
    QEMU_CONTRACT_PROBE_BUILD = 'PASS'
    Efi = $output
    Bytes = $item.Length
    SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash
    Log = $log
} | Format-List

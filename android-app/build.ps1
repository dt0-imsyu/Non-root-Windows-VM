$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$buildTools = Join-Path $sdk 'build-tools\36.0.0'
$androidJar = Join-Path $sdk 'platforms\android-36\android.jar'
$ndkBin = Join-Path $sdk 'ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin'
$javaBin = 'C:\Program Files\Android\Android Studio\jbr\bin'
$env:JAVA_HOME = Split-Path -Parent $javaBin
$env:Path = "$javaBin;$env:Path"
$out = Join-Path $root 'out'
New-Item -ItemType Directory -Force -Path $out, (Join-Path $out 'classes'), (Join-Path $out 'assets'), (Join-Path $out 'dex') | Out-Null
$wrapper = Join-Path $root '..\..\handoff-compact-2026-08-23\handoff-compact-2026-08-23\winavf-test\out\assets\u-boot-wrapper-v24.Image'
if ((Get-FileHash -LiteralPath $wrapper -Algorithm SHA256).Hash -ne '93EDA7C4BD54C33F85ADA6F05158C74EC6F5C3232F5CBA73846E5B442895F234') { throw 'U-Boot wrapper SHA-256 mismatch' }
Copy-Item -LiteralPath $wrapper -Destination (Join-Path $out 'assets\u-boot-wrapper-v24.Image') -Force
$source = Join-Path $root 'kernel-first\console-binary-echo.S'
& (Join-Path $ndkBin 'clang.exe') --target=aarch64-none-elf -c $source -o (Join-Path $out 'console-binary-echo.o')
if ($LASTEXITCODE -ne 0) { throw 'echo assembly failed' }
& (Join-Path $ndkBin 'ld.lld.exe') -m aarch64elf -Ttext=0 -o (Join-Path $out 'console-binary-echo.elf') (Join-Path $out 'console-binary-echo.o')
if ($LASTEXITCODE -ne 0) { throw 'echo link failed' }
& (Join-Path $ndkBin 'llvm-objcopy.exe') -O binary (Join-Path $out 'console-binary-echo.elf') (Join-Path $out 'assets\console-binary-echo.Image')
if ($LASTEXITCODE -ne 0) { throw 'echo image failed' }
$resources = Join-Path $out 'resources.zip'
& (Join-Path $buildTools 'aapt2.exe') compile --dir (Join-Path $root 'res') -o $resources
if ($LASTEXITCODE -ne 0) { throw 'resource compilation failed' }
& (Join-Path $buildTools 'aapt2.exe') link -I $androidJar --manifest (Join-Path $root 'AndroidManifest.xml') -A (Join-Path $out 'assets') -R $resources --min-sdk-version 36 --target-sdk-version 36 -o (Join-Path $out 'unsigned.apk')
if ($LASTEXITCODE -ne 0) { throw 'aapt2 link failed' }
$sources = Get-ChildItem (Join-Path $root 'src') -Recurse -Filter '*.java' | Select-Object -ExpandProperty FullName
& (Join-Path $javaBin 'javac.exe') -source 17 -target 17 -classpath $androidJar -d (Join-Path $out 'classes') $sources
if ($LASTEXITCODE -ne 0) { throw 'javac failed' }
$classes = Get-ChildItem (Join-Path $out 'classes') -Recurse -Filter '*.class' | Select-Object -ExpandProperty FullName
& (Join-Path $buildTools 'd8.bat') --min-api 36 --lib $androidJar --output (Join-Path $out 'dex') $classes
if ($LASTEXITCODE -ne 0) { throw 'd8 failed' }
& (Join-Path $javaBin 'jar.exe') uf (Join-Path $out 'unsigned.apk') -C (Join-Path $out 'dex') classes.dex
if ($LASTEXITCODE -ne 0) { throw 'APK packaging failed' }
$keystore = Join-Path $env:USERPROFILE '.android\debug.keystore'
if (-not (Test-Path $keystore)) { throw "Missing established signing key: $keystore" }
& (Join-Path $buildTools 'zipalign.exe') -f 4 (Join-Path $out 'unsigned.apk') (Join-Path $out 'aligned.apk')
if ($LASTEXITCODE -ne 0) { throw 'zipalign failed' }
& (Join-Path $buildTools 'apksigner.bat') sign --ks $keystore --ks-pass pass:android --key-pass pass:android --out (Join-Path $out 'WinAVF-test.apk') (Join-Path $out 'aligned.apk')
if ($LASTEXITCODE -ne 0) { throw 'APK signing failed' }
& (Join-Path $buildTools 'apksigner.bat') verify --verbose (Join-Path $out 'WinAVF-test.apk')
if ($LASTEXITCODE -ne 0) { throw 'APK verification failed' }
Get-FileHash -Algorithm SHA256 (Join-Path $out 'WinAVF-test.apk')

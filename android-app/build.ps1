$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$buildTools = Join-Path $sdk 'build-tools\36.0.0'
$androidJar = Join-Path $sdk 'platforms\android-36\android.jar'
$ndkBin = Join-Path $sdk 'ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin'
$javaHome = 'C:\Program Files\Android\Android Studio\jbr\bin'
$env:JAVA_HOME = Split-Path -Parent $javaHome
$env:Path = "$javaHome;$env:Path"
$out = Join-Path $root 'out'
Push-Location $root
New-Item -ItemType Directory -Force -Path $out, (Join-Path $out 'classes'), (Join-Path $out 'assets'), (Join-Path $out 'dex') | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $ndkBin 'clang.exe'))) { throw "Android NDK toolchain missing: $ndkBin" }
$knownGoodWrapper = Join-Path $root '..\..\handoff-compact-2026-08-23\handoff-compact-2026-08-23\winavf-test\out\assets\u-boot-wrapper-v24.Image'
$loaderImage = Join-Path $out 'assets\u-boot-wrapper-v24.Image'
if (-not (Test-Path -LiteralPath $knownGoodWrapper)) { throw "Known-good U-Boot wrapper missing: $knownGoodWrapper" }
if ((Get-FileHash -LiteralPath $knownGoodWrapper -Algorithm SHA256).Hash -ne '93EDA7C4BD54C33F85ADA6F05158C74EC6F5C3232F5CBA73846E5B442895F234') { throw 'Known-good U-Boot wrapper hash mismatch.' }
Copy-Item -LiteralPath $knownGoodWrapper -Destination $loaderImage -Force
$echoSource = Join-Path $root 'kernel-first\console-binary-echo.S'
$echoObject = Join-Path $out 'console-binary-echo.o'
$echoElf = Join-Path $out 'console-binary-echo.elf'
$echoImage = Join-Path $out 'assets\console-binary-echo.Image'
& (Join-Path $ndkBin 'clang.exe') --target=aarch64-none-elf -c $echoSource -o $echoObject
$LASTEXITCODE -eq 0 -or (throw 'console binary-echo assembly failed')
& (Join-Path $ndkBin 'ld.lld.exe') -m aarch64elf -Ttext=0 -o $echoElf $echoObject
$LASTEXITCODE -eq 0 -or (throw 'console binary-echo link failed')
& (Join-Path $ndkBin 'llvm-objcopy.exe') -O binary $echoElf $echoImage
$LASTEXITCODE -eq 0 -or (throw 'console binary-echo conversion failed')
& (Join-Path $buildTools 'aapt2.exe') link -I $androidJar --manifest (Join-Path $root 'AndroidManifest.xml') -A (Join-Path $out 'assets') --min-sdk-version 36 --target-sdk-version 36 -o (Join-Path $out 'unsigned.apk')
$LASTEXITCODE -eq 0 -or (throw 'aapt2 failed')
$sources = Get-ChildItem (Join-Path $root 'src') -Recurse -Filter '*.java' | Select-Object -ExpandProperty FullName
& (Join-Path $javaHome 'javac.exe') -source 17 -target 17 -classpath $androidJar -d (Join-Path $out 'classes') $sources
$LASTEXITCODE -eq 0 -or (throw 'javac failed')
$classFiles = Get-ChildItem (Join-Path $out 'classes') -Recurse -Filter '*.class' | Select-Object -ExpandProperty FullName
& (Join-Path $buildTools 'd8.bat') --min-api 36 --lib $androidJar --output (Join-Path $out 'dex') $classFiles
$LASTEXITCODE -eq 0 -or (throw 'd8 failed')
& (Join-Path $javaHome 'jar.exe') uf (Join-Path $out 'unsigned.apk') -C (Join-Path $out 'dex') classes.dex
$keystore = Join-Path $env:USERPROFILE '.android\debug.keystore'
if (-not (Test-Path $keystore)) {
  & (Join-Path $javaHome 'keytool.exe') -genkeypair -keystore $keystore -storepass android -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Android Debug,O=Android,C=US'
}
& (Join-Path $buildTools 'zipalign.exe') -f 4 (Join-Path $out 'unsigned.apk') (Join-Path $out 'aligned.apk')
$LASTEXITCODE -eq 0 -or (throw 'zipalign failed')
& (Join-Path $buildTools 'apksigner.bat') sign --ks $keystore --ks-pass pass:android --key-pass pass:android --out (Join-Path $out 'WinAVF-test.apk') (Join-Path $out 'aligned.apk')
$LASTEXITCODE -eq 0 -or (throw 'apksigner failed')
& (Join-Path $buildTools 'apksigner.bat') verify --verbose (Join-Path $out 'WinAVF-test.apk')
$LASTEXITCODE -eq 0 -or (throw 'APK verification failed')

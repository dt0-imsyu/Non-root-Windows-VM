# U-AVF app and operator guide (updated 2026-09-24)

The Android package remains `com.example.winavf`; the app label and launcher icon are **U-AVF**. The user-facing settings drawer has exactly two modes: **Windows** and **Linux**. The default selection is Windows and the selection is saved between app restarts. Diagnostic Vxx intents remain available to developers but are not shown as normal modes.

| Control | Action |
| --- | --- |
| Menu | Show/hide the compact top controls over the guest display |
| Settings | Slide out the mode selector from the right |
| Windows mode | Select the immutable audited Windows medium |
| Linux mode | Select the generic stock-Ubuntu profile and verified combined platform disk |
| Launch | Start the currently selected profile; do not use the wrong mode for an A/B |
| Stop | Request stop for the selected VM; does not delete its media |
| Logs | Slide up event and raw serial log panel |

The app does not download, build, or patch Windows/Ubuntu images on its own. The selected mode needs its previously audited files in `/sdcard/Android/data/com.example.winavf/files/`. Each launch checks expected size and SHA-256. The Linux mode currently also requires the stock ISO and 128 MiB platform ESP files even though runtime uses the verified one-disk combined image; this is a staging gate in the present research APK, not a general product requirement. See [the GNOME userspace report](GENERIC_UBUNTU_GNOME_USERSPACE_2026-09-24.md) for exact names and hashes.

Build/install in the established Windows host environment:

```powershell
cd C:\path\to\U-AVF\android-app
.\build.ps1
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb install -r .\out\WinAVF-test.apk
```

The build requires the locally retained known-good U-Boot wrapper and Android SDK/NDK paths specified in `build.ps1`. It is a debug-signed research APK, not a Play Store release. The application is deliberately debuggable for private-media diagnostic staging; do not distribute this build as a production security artifact.

Start only the UI (does not create a VM):

```powershell
& $adb shell 'am start -n com.example.winavf/.MainActivity'
```

Explicitly start the generic Linux combined-disk profile after staging and audit:

```powershell
& $adb shell 'am start -n com.example.winavf/.MainActivity --ez generic_ubuntu_combined true'
```

Relevant app-scoped logs: `/sdcard/Android/data/com.example.winavf/files/serial.log` for Windows, and `generic-ubuntu-serial.log` plus `generic-ubuntu-runtime-report.txt` for Linux. The app's ordinary Logs drawer reads the selected profile's current serial log. Do not mistake stale Vxx evidence for the generic Ubuntu profile.

Windows baseline SHA-256 must remain `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`. Linux `GNOME_USERSPACE = PASS`; `GNOME_VISIBLE_IN_APP = NOT_CONFIRMED`. Windows `EXIT_BOOT_SERVICES = PASS`; Windows post-EBS kernel/WinPE user mode is not yet confirmed.

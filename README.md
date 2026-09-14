# WinAVF — Windows on Android AVF research

WinAVF is an experimental, non-root research project for booting Windows ARM64
on a Samsung Galaxy Tab S11 through Android Virtualization Framework (AVF),
Samsung/MediaTek GenieZone, a kernel-first U-Boot loader, and EDK2.

It is **not** a Windows installer or a daily-driver VM product yet. Its value
today is a reproducible platform, a full evidence trail, and a working
pre-boot graphical experience without root, bootloader unlock, or modification
of Android system partitions.

---

## English

### What works

- Android AVF launches the custom one-vCPU VM on the Galaxy Tab S11.
- U-Boot and EDK2 boot correctly; Windows Boot Manager and `winload.efi` are
  reached.
- The original UEFI `ExitBootServices()` call returns successfully.
- EDK2 GOP frames are encoded as WAVF, exported through AVF console output,
  decoded in the Android app, and displayed in a `SurfaceView`.
- Repeated real UEFI screen updates are visible in the app.
- The app has a compact launch UI, a fixed-profile settings panel, and a local
  log panel. Once the guest produces a frame, controls collapse to a menu so
  the guest keeps the screen.
- Synthetic post-EBS probes prove guest RAM, UART, EL1 exceptions, GIC virtual
  timer PPI27, WFI wake-up, and reset on the product VM.

### Current limitation

`WINDOWS_POST_EBS` and `WINPE_USERLAND` are **not confirmed**. Windows reaches
the firmware handoff, but no supported observer has yet identified its first
post-EBS kernel location on stock Samsung firmware.

An independent firmware-only defect is reproducible: the advertised EL1
physical timer (`CNTP` / PPI30) does not retain a guest `CNTP_CVAL_EL0`
deadline after EBS, whereas the virtual timer (`CNTV` / PPI27) works. This is
reported separately and is **not claimed as the proven direct cause** of the
Windows stall. See the [Samsung submission kit](docs/SAMSUNG_GENIEZONE_SUBMISSION_KIT_2026-09-14.md).

### Repository layout

| Path | Purpose |
|---|---|
| `android-app/` | WinAVF launcher, AVF integration, WAVF decoder and full-screen renderer |
| `firmware/` | EDK2 platform boot-manager modifications and GOP/WAVF producer |
| `tools/` | Reproducible builders, image auditors, transactional patch/rollback helpers |
| `docs/` | Runtime reports, architecture decisions, evidence and vendor repro package |
| `STATE.md` | Current project state and confirmed boundaries |
| `CHECKLIST.md` | Ordered test checklist and handoff notes |

### Quick start: build and install the Android launcher

Requirements: Windows host, Android SDK Platform Tools, Android SDK API 36,
Android NDK as configured in `android-app/build.ps1`, a connected test tablet,
and USB debugging authorised for `adb`.

```powershell
cd C:\path\to\Non-root-Windows-VM\android-app
.\build.ps1

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb install -r .\out\WinAVF-test.apk
```

Open **WinAVF** on the tablet. **Launch** uses the existing, fixed and audited
product VM profile. It expects the known-good media to already be staged in
the app's external-files directory; the launcher intentionally refuses an
unknown-size image or an unverified transactional patch.

Do not treat a cloned repository as sufficient to run Windows: disk images,
firmware volumes, APK outputs and raw logs are intentionally local-only. Their
hashes and the exact materialisation procedures are recorded in `docs/` and
`tools/`; see [the local-artifact policy](docs/LOCAL_ARTIFACT_POLICY_2026-09-14.md).

### Safety rules

- Keep the immutable runtime baseline unchanged:
  `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.
- Use only a disposable copy for candidate images and require rollback/hash
  verification before and after each runtime test.
- Never use scripts here against a physical host/tablet disk.
- Do not change BCD, signed Windows binaries, Android system files, or
  firmware merely to try a speculative workaround.
- Read the corresponding report before repeating any numbered runtime test.

### Reporting the platform defect

Submit the compact report in the Samsung submission kit through **Samsung
Members → Support → Error reports**, enable **Send system log data**, then
escalate the resulting report ID through Samsung Support. The kit contains a
full engineering report, evidence hashes, and a privacy-safe attachment list.

---

## Русская версия

### Что уже работает

- Android AVF запускает пользовательскую VM с одним vCPU на Galaxy Tab S11.
- U-Boot и EDK2 загружаются; достигнуты Windows Boot Manager и `winload.efi`.
- Исходный вызов UEFI `ExitBootServices()` успешно возвращается вызывающему
  загрузчику Windows.
- Кадры EDK2 GOP кодируются в WAVF, выходят через AVF console, декодируются
  Android-приложением и отображаются в `SurfaceView`.
- В приложении видны реальные повторные изменения интерфейса UEFI.
- В launcher есть компактный запуск, настройки фиксированного профиля и
  вкладка логов. После первого кадра элементы скрываются в меню, чтобы экран
  практически целиком занимал гость.
- Synthetic post-EBS probes подтвердили RAM, UART, исключения EL1, виртуальный
  таймер GIC PPI27, пробуждение из WFI и reset именно на product VM.

### Текущее ограничение

`WINDOWS_POST_EBS` и `WINPE_USERLAND` пока **не подтверждены**. Windows
проходит firmware handoff, но на stock Samsung пока нет доступного observer,
который честно укажет её первую kernel-точку после EBS.

Отдельно найден firmware-only дефект: advertised physical timer EL1
(`CNTP` / PPI30) не сохраняет deadline `CNTP_CVAL_EL0` после EBS, тогда как
virtual timer (`CNTV` / PPI27) работает. Это **не объявлено доказанной
причиной** зависания Windows. Готовый отчёт для Samsung находится в
[submission kit](docs/SAMSUNG_GENIEZONE_SUBMISSION_KIT_2026-09-14.md).

### Структура репозитория

| Путь | Назначение |
|---|---|
| `android-app/` | Launcher WinAVF, AVF-интеграция, WAVF decoder и renderer |
| `firmware/` | Изменения EDK2 boot manager и GOP/WAVF producer |
| `tools/` | Сборщики, offline-аудиторы, transactional patch и rollback scripts |
| `docs/` | Отчёты runtime, архитектурные решения, доказательства и vendor repro |
| `STATE.md` | Текущее состояние и подтверждённые границы |
| `CHECKLIST.md` | Последовательность тестов и handoff-заметки |

### Быстрый старт: собрать и поставить launcher

Нужны Windows-хост, Android SDK Platform Tools, Android SDK API 36, Android
NDK из конфигурации `android-app/build.ps1`, подключённый планшет и разрешённый
USB debugging.

```powershell
cd C:\path\to\Non-root-Windows-VM\android-app
.\build.ps1

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb install -r .\out\WinAVF-test.apk
```

Откройте **WinAVF** на планшете. Кнопка **Запуск** использует существующий
проверенный VM-профиль. Known-good media должны быть заранее размещены во
внешней папке приложения: launcher намеренно не принимает неизвестный образ
или непроверенный transactional patch.

Обычного `git clone` недостаточно для запуска Windows: образы дисков, firmware
volumes, APK и raw logs специально оставлены локальными. Их SHA-256 и точные
процедуры materialize/audit записаны в `docs/` и `tools/`; см.
[политику локальных артефактов](docs/LOCAL_ARTIFACT_POLICY_2026-09-14.md).

### Правила безопасности

- Не менять immutable baseline:
  `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.
- Любой candidate делать только из отдельной копии и подтверждать rollback и
  hash до/после runtime.
- Не применять скрипты к физическим дискам компьютера или планшета.
- Не менять BCD, подписанные Windows binaries, Android system files или
  firmware ради неподтверждённой гипотезы.
- Перед повтором numbered runtime-теста читать его отчёт в `docs/`.

### Как сообщить о дефекте платформы

Отправьте короткий текст из submission kit через **Samsung Members → Support
→ Error reports**, включите **Send system log data**, сохраните номер отчёта и
передайте его в Samsung Support для эскалации в firmware / GenieZone команду.
В kit уже есть полный технический текст, hashes и список безопасных вложений.

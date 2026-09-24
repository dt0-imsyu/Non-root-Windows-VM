# U-AVF

![U-AVF icon](android-app/res/drawable/ic_uavf_brand.png)

U-AVF is an experimental, non-root Android Virtualization Framework (AVF) launcher for ARM64 guests on a Samsung Galaxy Tab S11. It has separate **Windows** and **Linux** modes. The project uses GenieZone/crosvm, a kernel-first U-Boot stage, and EDK2. It does not unlock the bootloader or modify Android system partitions.

This is a research build, **not** a ready-to-install Windows or Ubuntu VM. Large guest media and firmware artifacts are not distributed in Git. The APK alone cannot boot either guest without verified local media.

## English

### Current status

| Mode | Confirmed | Still missing |
| --- | --- | --- |
| Windows | U-Boot → EDK2 → Windows Boot Manager → `winload.efi` → successful original `ExitBootServices()` return; graphical UEFI frames appear in the app | Windows kernel/WinPE user-mode progress after EBS and Windows desktop |
| Linux | An untouched Ubuntu 24.04.5 Desktop ARM64 ISO boots through Linux `/init`, systemd, GDM, and GNOME Shell; virtio-GPU binds and creates a DRM framebuffer | GNOME desktop pixels in the app and user input; a capset timeout still needs investigation |

Linux's `GNOME_USERSPACE = PASS` is evidenced by the final serial log, including `GNOME Shell started` and GDM session registration. **It is not a claim that the GNOME desktop is visible or interactive in U-AVF yet.** Read the [generic Ubuntu runtime report](docs/GENERIC_UBUNTU_GNOME_USERSPACE_2026-09-24.md).

Windows reaches EBS, but `WINDOWS_POST_EBS` and `WINPE_USERLAND` remain unconfirmed. An independently reproduced EL1 physical timer issue is documented for Samsung; it has **not** been proven to cause the Windows stall.

### Using the app

1. Build and install the development APK with the established Android SDK/NDK environment:

   ```powershell
   cd C:\path\to\U-AVF\android-app
   .\build.ps1
   $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
   & $adb install -r .\out\WinAVF-test.apk
   ```

2. Open **U-AVF**. In **Settings**, select **Windows mode** or **Linux mode**. The choice is remembered. **Launch** starts the selected VM, **Stop** requests it to stop, and **Logs** shows local event and serial output. The guest display occupies the main screen; the top controls can be collapsed.
3. Stage only the audited media required by the chosen mode. The app checks exact file sizes and SHA-256 hashes before launch. Windows uses the immutable known-good image and reversible firmware patch. Linux uses the verified stock Ubuntu ISO plus a separate platform disk containing the boot chain; the ISO itself is never edited. See [STATE.md](STATE.md), the [operator guide](docs/APP_UI_AND_OPERATOR_GUIDE_2026-09-21.md), and the [generic Ubuntu report](docs/GENERIC_UBUNTU_GNOME_USERSPACE_2026-09-24.md) before attempting a run.

The build currently references a known-good U-Boot wrapper in the developer's local workspace, so a fresh clone does not build or run standalone. This limitation is intentional and should not be hidden by publishing unaudited guest images.

### Safety and repository layout

- Preserve the immutable Windows baseline SHA-256: `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`.
- Use disposable candidates and verify their hashes and rollback. Never target a physical disk with image-editing scripts.
- `android-app/`: launcher, AVF integration, pre-EBS WAVF decoder and renderer.
- `firmware/`: EDK2 platform and GOP producer changes.
- `tools/generic-ubuntu/`: platform-disk builder and offline auditors; no modified stock ISO.
- `docs/`, `STATE.md`: evidence, procedures, limitations, and milestones.
- [Local artifact policy](docs/LOCAL_ARTIFACT_POLICY_2026-09-14.md): images, firmware binaries, APK outputs, and raw runtime logs stay outside ordinary Git commits.

The physical-timer report for Samsung is available in the [submission kit](docs/SAMSUNG_GENIEZONE_SUBMISSION_KIT_2026-09-14.txt).

## Русский

### Что работает

| Режим | Подтверждено | Пока не готово |
| --- | --- | --- |
| Windows | U-Boot → EDK2 → Windows Boot Manager → `winload.efi` → успешный возврат из оригинального `ExitBootServices()`; графический UEFI виден в приложении | Подтверждение выполнения ядра/WinPE после EBS и рабочий стол Windows |
| Linux | Неизменённый официальный Ubuntu 24.04.5 Desktop ARM64 ISO доходит до `/init`, systemd, GDM и GNOME Shell; virtio-GPU создаёт DRM framebuffer | Картинка GNOME в приложении и управление; требуется разобраться с capset timeout |

`GNOME_USERSPACE = PASS` означает подтверждённый запуск GNOME Shell по serial-логу. Это **ещё не** означает, что рабочий стол виден на экране U-AVF или им можно управлять. Подробности — в [отчёте](docs/GENERIC_UBUNTU_GNOME_USERSPACE_2026-09-24.md). Windows доходит до EBS, но `WINDOWS_POST_EBS` и `WINPE_USERLAND` пока не подтверждены. Найденный отдельно дефект физического таймера не объявляется доказанной причиной остановки Windows.

### Как пользоваться

1. Соберите тестовый APK командой `android-app\build.ps1` в подготовленном Windows/Android SDK окружении и установите `android-app\out\WinAVF-test.apk` через ADB. Обычный клон репозитория **не содержит** больших образов и локального проверенного U-Boot wrapper, поэтому сам по себе не готов к запуску VM.
2. Откройте **U-AVF**. В **Settings** выберите **Windows mode** или **Linux mode**. Выбор запоминается. **Launch** запускает выбранный режим, **Stop** запрашивает остановку VM, **Logs** показывает журнал. Экспериментальные диагностические профили не входят в обычный выбор режимов.
3. До запуска разместите только проверенные файлы для выбранного режима. Приложение сверяет размер и SHA-256. Windows использует неизменяемый known-good образ и обратимый firmware patch; Linux — отдельный платформенный диск и официальный ISO без изменения его байтов. Точные ограничения и методы: [STATE.md](STATE.md), [руководство оператора](docs/APP_UI_AND_OPERATOR_GUIDE_2026-09-21.md), [отчёт Ubuntu](docs/GENERIC_UBUNTU_GNOME_USERSPACE_2026-09-24.md).

Нельзя менять baseline Windows с SHA-256 `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` или запускать скрипты редактирования образа на физическом диске. Образы, firmware binaries, APK и сырые логи намеренно не лежат в обычном Git; см. [политику артефактов](docs/LOCAL_ARTIFACT_POLICY_2026-09-14.md). [Отчёт для Samsung](docs/SAMSUNG_GENIEZONE_SUBMISSION_KIT_2026-09-14.txt) описывает отдельный дефект таймера.

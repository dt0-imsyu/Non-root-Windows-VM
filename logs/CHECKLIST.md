# WinAVF: Galaxy Tab S11 → Windows 11 ARM64

Цель: получить первый **видимый** экран Windows Boot Manager / WinPE на планшете, не меняя загрузчик Android, разделы устройства или прошивку планшета.

## Статус

- [x] Сохранены исходные рабочие образы и журналы.
- [x] U-Boot передаёт управление второй стадии EDK2.
- [x] Восстановлен сохранённый Windows Boot Manager milestone: `Loading files...` на физическом планшете.
- [x] Восстановлены сохранённые firmware и загрузочный носитель без изменений автоматизации.
- [x] Подтверждено Windows Boot Manager / `Loading files…` в serial-логе.
- [x] Расширить единственный r2-диск до полного installer-носителя: `BOOTAA64.EFI`, `boot.wim`, `install.swm` и Setup-файлы — без добавления PCI‑устройств.
- [x] Подтвердить `Loading files... = PASS` на полном installer в том же единственном `virtio-blk 00:04.0`.
- [x] GPU включён (`1AF4:1050`), а динамический boot path нашёл `1AF4:1042` на `00:05.0` и передал управление `BOOTAA64.EFI`.
- [x] GPU Windows-loader pass: после `START_IMAGE` crosvm остался запущен и прочитал 615 600 KiB (практически весь `boot.wim`), при этом графический loader больше не зеркалирует строку `Loading files...` в serial.
- [x] Проверен доступ к видимому WinPE после GPU-loader pass: отдельная Android surface и RFB/VNC endpoint не предоставлены текущим AVF runtime.
- [x] Static graphics audit: ArmVirtKvmTool includes `VirtioGpuDxe`; the current GOP adaptation provides a reserved, physical BGRA LFB and preserves the virtio scanout at EBS.
- [x] Static/runtime API audit: this resource has no ordinary-app FD/handle path; the Android native display service remains privileged-only.
- [x] Rejected firmware-resident post-EBS relay: no autonomous UEFI runtime execution mechanism exists.
- [x] Selected product architecture: `EARLY_WINDOWS_DISPLAY_RELAY = VIABLE` via a signed ARM64 Windows display-only relay plus public vsock and the app's own Android renderer.
- [ ] Дойти до WinPE/Setup и получить первый видимый экран (ожидает гостевой display/input transport).
- [ ] Отдельно, без изменения firmware: проверить, сохраняет ли AVF загрузочный диск первым (`00:04.0`) при добавлении target вторым (`00:05.0`).
- [ ] Если порядок не сохраняется — для proof использовать один большой виртуальный диск с installer- и Windows-разделами.
- [ ] Получить первый видимый Windows/WinPE-экран на Galaxy Tab S11.
- [ ] Сохранить финальные образы, хеши, serial-лог и инструкцию повторения.

## Тестовая фаза перед display implementation

| Тест | Статус | Runtime-доказательство |
| --- | --- | --- |
| Test 1 — WinPE userland | **FAIL (current media)** | r9 (`startnet.cmd`) и r10 (`winpeshl.ini`) не создали marker; r11 с `winpeshl.ini → wpeutil reboot` не перезагрузил VM после полной загрузки WIM. В index 2 нет `viostor`/`virtio` Windows-драйвера, что объясняет отсутствие доступа WinPE к virtio-blk. |
| Test 2 — Windows vsock capability | BLOCKED | Запрещено начинать до `WINPE_USERLAND = PASS`. |
| Test 3 — hello over vsock | BLOCKED | Зависит от Test 1 и Test 2. |
| Test 4 — vsock performance | BLOCKED | Зависит от двустороннего hello. |

Текущая диагностическая VM: `winavf-winpe-userland-r9`. Это отдельный writable-клон r6 с **одним** virtio-диском; firmware, PCI enumeration, dynamic disk lookup и r3/r6 baseline не меняются.

## Текущий блокер для следующего шага

Нативный Android display broker не доступен `untrusted_app`; нельзя считать
virtio-gpu resource доступным Android-приложению только потому, что он
сохраняется после EBS. Следующий шаг ограничен offline preflight: проверить
готовый production-signed ARM64 пакет `viogpudo` + `viosock`, его INF и
совместимость с уже подтверждённым GPU `1AF4:1050`. До этого не менять WIM,
BCD, firmware или baseline image.

Runtime r6: crosvm `crosvm_winavf-gpu-dynamic-loader-r6` остаётся жив после `BOOTAA64.EFI`; SurfaceFlinger содержит только UI launcher, а все доступные TCP listeners отклоняют RFB handshake. В API VirtualMachine также нет метода передачи guest framebuffer в Android View. Это ограничение host display transport, а не загрузочного диска, firmware или WinPE.

Проверка r4 подтвердила, что даже `DisplayConfig` без `GpuConfig` автоматически добавляет `1af4:1050` на `00:01.0`, а единственный диск становится `00:05.0`. Это не является допустимым путём; исходная однодисковая конфигурация восстановлена как r5.

## Текущая точка

Baseline r3 остаётся неизменным: полный единый installer-диск достигает `Loading files...` на `00:04.0`. Отдельный r6 использует клон того же installer с firmware динамического поиска: при GPU `1AF4:1050` блоковый virtio-диск сдвинулся на `00:05.0`, был найден через PCI vendor/device `1AF4:1042` и передан Windows Boot Manager. После этого crosvm продолжил работу и прочитал объём, соответствующий `boot.wim`.

## Ограничения безопасности

- Только пользовательское приложение AVF и его private/external-файлы.
- Никаких root, unlock, flash, изменения Android-разделов или физических дисков.
- Каждый новый тест использует отдельное имя ВМ и отдельный клон загрузочного образа.

## Доказательства

- Последний подтверждённый лог: `build-logs/serial-loader-pass-restore-r2-reconfirmed-20260825.log`.
- Полный installer, подтверждённый runtime-логом: `build-logs/serial-single-disk-installer-r3-20260825.log`.
- Недопустимый display-only probe: `build-logs/serial-single-disk-installer-r4-display-only-20260825.log`.
- GPU + dynamic boot path runtime-лог: `build-logs/serial-gpu-dynamic-loader-r6-20260825.log`.
- GPU media (клон r3): `handoff-compact-2026-08-23/handoff-compact-2026-08-23/windows-headless-media/win11-single-disk-installer-gpu-dynamic-r1.img`; embedded firmware SHA-256 `950F6B630C9A4131EF6326DBFE39CDA39929C4404E7EE357CB4F7A50D1A20C16`.
- Восстановленная прошивка: `firmware-work/edk2/artifacts/KVMTOOL_EFI-pci-cam-windows-loader-pass.fd`.
- Восстановленный носитель: `handoff-compact-2026-08-23/handoff-compact-2026-08-23/windows-headless-media/win11-loader-pass-restore-r1.img`.

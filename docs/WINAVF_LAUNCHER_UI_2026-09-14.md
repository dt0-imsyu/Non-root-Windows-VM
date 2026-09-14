# WinAVF launcher UI

The Android launcher is now a compact product surface rather than a visible
test-control panel.

## Launch state

The initial screen exposes only:

- **Запуск** — starts the preserved transactional product path;
- **Настройки** — shows the intentionally fixed, verified VM profile;
- **Логи** — shows bounded in-app status history and, when present, the tail
  of the saved serial log.

Diagnostic actions remain explicit intent extras; they are not presented as
ordinary product controls.

## Guest-display state

After the first valid GOP/WAVF frame, launch panels and status text hide so the
guest has the full display. A compact menu button remains at the upper left;
it restores the controls without stopping or altering the VM.

The UI does not change AVF topology, firmware, media, BCD, or the established
frame decoder/renderer contract.

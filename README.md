# Non-root Windows VM — WinAVF research snapshot

Snapshot of the Galaxy Tab S11 / Android Virtualization Framework worktree.

Included:

- Android AVF launcher source (`android-app/`);
- EDK2 dynamic virtio-block boot-path source (`firmware/`);
- current checklist and selected serial runtime logs (`logs/`);
- the current test result and exact next step below.

## Preserved baselines

- **r3** — single full installer, Windows Boot Manager / `Loading files...`.
- **r6** — GPU enabled, dynamic discovery of `1AF4:1042` at `00:05.0`, then `BOOTAA64.EFI`.
- **r10** — final startup-script diagnostic clone.

The large VM media are deliberately not committed: GitHub normal Git cannot store the approximately 80 GiB image set.  Keep them locally and identify them by the paths recorded in `logs/CHECKLIST.md`.

## Current test status

- GPU Windows-loader path: PASS.
- WinPE startup-marker variants r9/r10: no marker.
- r11 invokes `wpeutil reboot` through `winpeshl.ini`; it did not reboot during the observed runtime window.
- `boot.wim` index 2 has no `viostor`/virtio driver. This must be corrected for WinPE access to the installer disk, but is **not** treated as proof that WinPE userland cannot start from RAM.

Next test: integrate ARM64 `viostor` into boot.wim index 2, verify its service is boot-start and supports PCI `1AF4:1042`, then repeat the r11 reboot test. Do not change EDK2, PCI topology, GPU configuration, dynamic disk discovery, or r6.

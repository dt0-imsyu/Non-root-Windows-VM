# Shell KD BCD preflight — 2026-09-07

## Result

```text
SHELL_KD_MEDIA_CLONE             = PASS
BCD_BOOTDEBUG_CANDIDATE          = PASS
BCD_BOOTDEBUG_INJECTED           = PASS
SHELL_WINDOWS_KD_RUNTIME         = NOT_RUN
WINDOWS_KD_HANDSHAKE             = NOT_TESTED
```

The immutable Android external baseline was read without modification:

```text
/sdcard/Android/data/com.example.winavf/files/win11-gop-ebs-r1.img
size    = 9,126,805,504 bytes
SHA-256 = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

It was copied to the separate host-only clone
`E:\winavf-kd-shell-clone-20260907-baseline.img`; its full SHA-256 matched
the immutable baseline before any BCD work. This filename is now historical:
after the injection below, the file is a **KD diagnostic candidate**, not a
baseline image. The Android baseline remains untouched.

## Offline BCD candidate

The FAT short-name path is `\EFI\MICROS~1\BOOT\BCD`. The original file was
extracted read-only:

```text
baseline size    = 16,384 bytes
baseline SHA-256 = B90EF16B94C3DDA7D76CC39840BEFAA9786887517445C3B6F47EBC806D0AB105
```

An elevated BCDEdit run changed only a separate extracted copy. It set:

```text
{default}.bootdebug = Yes
{default}.debug     = Yes
{dbgsettings}.debugtype = Serial
{dbgsettings}.debugport = 1
{dbgsettings}.baudrate  = 115200
```

No `testsigning`, `nointegritychecks`, firmware, WIM, driver, or signed binary
was changed. The candidate has SHA-256
`DE6698BF9CCF5205403A5E8ED1D6CC5E2790A3E3EF23F4539B512D1C0DFB9A11`.

## Standard FAT injection with mtools

GNU mtools 4.0.49 was already present at
`C:\msys64\mingw64\bin\`. It accessed the existing FAT32 ESP in the raw
clone directly at byte offset `1,048,576` using:

```text
E:/winavf-kd-shell-clone-20260907-baseline.img@@1048576
```

No VHD, formatter, qemu conversion, custom allocator, or manual FAT write was
used. `mdir` read the volume (`WINSETUP`, serial `D6E9-20DC`) and recursively
traversed it. `mcopy -o` replaced only
`\EFI\Microsoft\Boot\BCD`; mtools allocated the one necessary additional
8,192-byte cluster and maintained the FAT itself.

The original BCD was retained separately and re-extracted before injection:

```text
original size    = 16,384 bytes
original SHA-256 = B90EF16B94C3DDA7D76CC39840BEFAA9786887517445C3B6F47EBC806D0AB105
original chain   = 2937 -> 2938
```

The resulting BCD re-extracts byte-for-byte as the prepared KD candidate:

```text
injected size    = 20,480 bytes
injected SHA-256 = DE6698BF9CCF5205403A5E8ED1D6CC5E2790A3E3EF23F4539B512D1C0DFB9A11
injected chain   = 884163 -> 884164 -> 884165
```

The recursive mtools read completed (1,587 output lines), the root directory
and volume identity remain readable, and the recursive name manifest is
identical before/after (0 additions/removals). The only intended semantic file
change is BCD; FAT allocation/metadata change is the standard consequence of
growing it. Full-clone hashes are:

```text
before mtools = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
after mtools  = 563DA01DB2DADDA202B8475D280E064F0C5C5B60DC07ACA61B6009C38147C196
```

The host-only candidate has not been transferred to Android and no Windows VM
or KD bridge has been run.

## Evidence and safe next action

All clone and BCD artifacts are retained in
`build-logs/kd-shell-clone-20260907/`, including the mtools readback/audit in
`mtools-bcd-injection/`. The exact elevated, offline-only configuration command
is retained as `tools/shell-serial-loopback/configure-offline-kd-bcd.ps1`.

The prerequisites are now satisfied for a separately authorized, one-shot
shell-owned Windows KD diagnostic: the shell-only COM1 pipe loopback is binary
transparent and the disposable BCD candidate has been injected. Before any
such run, the shell-VM topology must be compared against WinAVF and the
host-side bridge must be prepared as raw bytes, not a PTY.

## First standard VHD materialization attempt

A single elevated `diskpart` fixed-VHD attempt was made after the above
preflight. It created only `E:\winavf-kd-shell-clone-20260907-work.vhd` and
then detached it in the script's cleanup path. It produced neither the planned
raw KD candidate nor a materialization report, so no candidate was staged to
Android and no Windows VM was run. The original raw clone was used only as a
read source.

The elevated child did not preserve its failure text. Repeating a full sector
copy without first adding bounded error capture would be an uninformative
second storage attempt, so this workflow is stopped here. The VHD is retained
for inspection; it must not be used as a runtime image or overwrite another
artifact.

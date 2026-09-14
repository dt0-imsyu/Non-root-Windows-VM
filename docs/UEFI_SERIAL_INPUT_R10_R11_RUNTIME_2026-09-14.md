# Product UEFI serial-input audit: r10/r11 — 2026-09-14

## Question

Can the app-owned AVF `getConsoleInput()` stream deliver a byte to the
existing EDK2 `SimpleTextIn` provider on the same product VM that renders GOP
frames through console output?

## Scope and safety

Only a reversible 2 MiB firmware-range patch was applied to the app-private
copy of the known-good runtime image.  No Windows file, WIM, BCD, driver,
Android system setting (after cleanup), or immutable product image was
persistently changed.

Immutable product baseline:

```text
2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
```

The final r11 bundle changed exactly:

```text
offset = 7250927616
length = 2097152
before = 3DAF5427A9023BFE8D4044932D4020364021BC942A33DF77006FC1536479F995
after  = A6853EEBD96FB836F0354C79BCAAD2F7994DD87578B58E5582D35D95777B0FC7
patch  = D89917DA1A404DF0C798E9F1136EEF3FD1A97BE9F99644564011C33ADA4AFA6B
```

Both forward and rollback simulations passed before the tablet run.  After
each runtime, the launcher rollback passed, no VM remained, hidden API policy
was restored to `null`, and the external image again had the exact baseline
hash.

## Firmware observer

`PlatformBootManagerAfterConsole()` retains the existing GOP frame sequence
and direct removable-media boot.  Before that one-shot boot it invokes a
diagnostic-only `SimpleTextIn.ReadKeyStroke()` loop.  An `ESC` produces:

```text
AVF_UEFI_ESC_RECEIVED
AVF_UEFI_ESC_DRAW
AVF_UEFI_ESC_FRAME
```

The r10 five-second window exposed a console-output batching problem: the host
saw `AVF_UEFI_INPUT_WINDOW` only together with the later timeout.  r11 made no
platform, media, or protocol change; it extended that same polling interval to
30 seconds.  r11 FD:

```text
A6853EEBD96FB836F0354C79BCAAD2F7994DD87578B58E5582D35D95777B0FC7
```

The r11 build completed successfully in the retained EDK2 environment.

## Final bounded product run

Because TX batches the idle-window marker, the final APK did not wait for that
marker.  After EDK2's earlier `Press ESCAPE for boot options` text appeared,
it wrote and flushed byte `0x1B` every 250 ms for at most 55 seconds, stopping
early only on the firmware acknowledgement.

The resulting app report was:

```text
transport=APP_CONSOLE_INPUT_TO_EDK2_SERIAL_CONIN
mode=BOUNDED_PERIODIC_ESC_UNTIL_FIRMWARE_ACK
promptSeen=true
payloadHex=1B
uartWrites=220
uartWrite=PASS
framesBefore=0
framesAfter=5
firmwareEscapeAcknowledged=false
result=UART_WRITE_PASS_RESPONSE_NOT_OBSERVED
```

The raw product serial log independently contains:

```text
AVF_UEFI_INPUT_WINDOW seconds=30
AVF_UEFI_INPUT_TIMEOUT
```

and contains none of the three acknowledgement records.  Thus the writes
covered the actual 30-second firmware polling phase, rather than merely
preceding it.

## Verdict

```text
APP_OWNED_CONSOLE_INPUT_API            = AVAILABLE
APP_OWNED_CONSOLE_INPUT_WRITE          = PASS
APP_OWNED_BINARY_LOOPBACK_DISPOSABLE   = PASS (prior isolated control)
PRODUCT_TTYS0_TO_EDK2_SIMPLETEXTIN     = NOT_CONFIRMED
PRODUCT_UEFI_SERIAL_ESC_CONSUMPTION    = NOT_OBSERVED
AVF_UEFI_SERIAL_INPUT_TRANSPORT        = BLOCKED_ON_PRODUCT_TOPOLOGY
GRAPHICAL_UEFI_INPUT                   = NOT_CONFIRMED
```

This is not a claim that Android rejected the writes: `OutputStream.write()`
and `flush()` completed 220 times.  The remaining ambiguity is below that API:
the product VM's console-input endpoint is not reaching the EDK2 TerminalDxe
consumer, is mapped to a different guest endpoint, or drops inbound data in
the AVF/crosvm path.  The app cannot distinguish those possibilities without
vendor-side trace access.

## Consequence

Do not implement a supposedly interactive UEFI menu around serial arrows or
Enter yet.  Pre-EBS GOP output remains product-ready; a visible Stop control
in the Android app can be implemented independently.  Arrow/Enter navigation
requires either a separately proven AVF input-device path or vendor support
for product console RX routing.

Raw artifacts are retained under `build-logs/uefi-serial-input-r10-20260914/`
and `build-logs/uefi-serial-input-r11-20260914/`.

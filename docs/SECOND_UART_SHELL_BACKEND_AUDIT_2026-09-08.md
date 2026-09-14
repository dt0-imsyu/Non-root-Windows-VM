# Second-UART shell backend audit — 2026-09-08

## Scope

This is a source/evidence audit following r10. No VM was created, no Windows
clone or product image was changed, and no firmware, BCD, WIM, APK, or system
component was modified.

## Result

```text
SECOND_UART_SHELL_BACKEND = NOT_EXPOSED
SHELL_SECOND_UART_LOOPBACK = BLOCKED
WINDOWS_KD_HANDSHAKE = NOT_OBSERVED
```

The r10 installed-table evidence identifies the ACPI DBG2 UART as `0x2F8`.
The current AVF/crosvm topology exposes the host bridge only for the distinct
console UART at `0x3F8` (`ttyS0`). It does not expose an RX/TX endpoint for
the `0x2F8` UART to `adb shell`.

## Exact evidence

The retained `virtualizationservice` source in `crosvm.rs` constructs:

```text
ttyS0: --serial=type=file,path=<console>,input=<console-in>,hardware=serial,num=1
ttyS1: --serial=type=file,path=<failure-pipe>,hardware=serial,num=2
```

`add_console_arg()` accepts only `ttyS0` and `hvc0` as a console-input device;
any other value is rejected as `Unsupported serial device`. It passes the
caller-controlled input FD to the serial device only when the device is
`ttyS0`. `add_failure_pipe()` creates serial `num=2` as an output-only pipe;
the service's own `failure_reader` consumes that pipe and no input FD is added.

This is not merely an old-source inference. The preserved process capture from
the exact product r9 runtime contains the same actual crosvm arguments:

```text
--serial=type=file,path=/proc/self/fd/27,input=/proc/self/fd/28,hardware=serial,num=1
...
--serial=type=file,path=/proc/self/fd/31,hardware=serial,num=2
```

The `num=2` entry has no `input=` parameter. r10 then independently proved
that this second serial identity is the one emitted as Windows DBG2 `0x2F8`.

The public shell CLI has only one `--console` and one `--console-in` option;
it does not accept arbitrary crosvm `--serial` arguments. Pointing the raw
JSON `console_input_device` at `ttyS1` cannot help: the service rejects it
before crosvm launch. Thus a shell-only byte-exact loopback for `0x2F8` cannot
be truthfully attempted, and launching one would provide no valid result.

## Consequence

The earlier framed bridge remains valid only for `ttyS0` / `0x3F8`. It cannot
exercise the debug UART advertised to Windows in DBG2. This fully explains why
the prior serial-KD runs had a working bridge while receiving no KD target
packet; it does not prove the post-EBS hang cause.

The only minimal next diagnostic candidate is now a separately authorized
firmware-only A/B that changes the **debug ACPI description only** so DBG2 and
the serial SSDT's `COM0._CRS` identify the already-proven `0x3F8` console UART.
It must leave SPCR, Windows media, BCD, drivers, and Android code untouched.
No such patch has been built or applied in this audit.

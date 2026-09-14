# Product app-owned KD at `IMAGE_AUDIT` gate — 2026-09-09

## Scope

One bounded product-equivalent diagnostic run used only the already audited
merged BCD+r11 transaction.  It did not rebuild or alter the APK, firmware,
WIM, BCD candidate, signed Windows binaries, or Android system software.

| Item | Value |
|---|---|
| immutable external baseline | `2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` |
| merged BCD+r11 patch | `4F2EA0AE40E6467608EA753E1368EC3F97C03A4C11DA9B2A17782D62B93742E6` |
| gate | `IMAGE_AUDIT start enter` |
| KD duration after gate | 100 seconds |

The host waited for Android's durable `state=LISTENING` record before its sole
TCP connection.  Bridge authentication, marker gating, named-pipe connection,
and raw pumps all completed.

## Runtime facts

```text
ANDROID_BRIDGE_LISTENING=1
ANDROID_BRIDGE_AUTHENTICATED=1
GATE_MARKER_OBSERVED=IMAGE_AUDIT start enter
KD_PIPE_CONNECTED=1
RAW_KD_BRIDGE_RUNNING=1
BOUND_REACHED=SECONDS_100
```

Artifacts: `build-logs/product-kd-image-audit-kd-runtime-r2-20260909-181230/`.

| Stream | Bytes | SHA-256 |
|---|---:|---|
| guest UART → KD | 1,290,832 | `F9DFDEE4EE72A209204042CB3551F3688C17ADB60B1D3D4B3612FFE8AEC13624` |
| KD → guest UART | 450 | `90E9DCF5A2DBB178117753D5B84D476A32FDE8573A3A001554531EA45F6564DC` |
| KD log | 1,329 | `73ADBF877817460FE6C998E6399D6D8B23B9B1B746912B32814B776F945D8CE9` |

The first debugger bytes are the expected repeated raw `69 69 69 69 06 ...`
serial KD synchronization traffic.  They were released only after the full
gate marker, so this run did not repeat the known U-Boot collision.

`kd.exe` opened the named pipe but remained at `Waiting to reconnect...`; the
guest stream contained no target KD packet.  Its final printable serial tail
was:

```text
IMAGE_AUDIT start enter handle=17E8E5418
CONVERT_AUDIT miss ... status=Not Found
CONVERT_AUDIT request ... status=Not Found
```

There was no complete `BES` record in this KD-enabled capture.  The historical
r11 baseline capture has the same final audit lines followed immediately by
`BES`, but that difference alone does not prove a kernel fault: the BCD debug
configuration and KD synchronization are intentionally different in this
experiment.

## Classification

```text
IMAGE_AUDIT_GATE_OBSERVED       = PASS
GATED_NO_PREBOOT_KD_TX          = PASS
KD_HOST_NAMED_PIPE              = PASS
PRODUCT_APP_KD_BRIDGE           = PASS
WINDOWS_KD_HANDSHAKE            = NOT_OBSERVED
EXIT_BOOT_SERVICES_THIS_KD_RUN  = NOT_OBSERVED
WINDOWS_KERNEL_ENTRY            = UNKNOWN
```

This proves the diagnostic transport to the intended product COM1 but does
not yield a Windows debugger target.  Do not reinterpret the missing `BES` as
a generic firmware regression and do not try more BCD/firmware variations in
the same session.

## Cleanup

The bridge force-stopped only the WinAVF app, performed its transactional
private-image rollback, and restored hidden API policy.  Direct audit after
the run confirmed:

```text
RESULT=PASS
BASELINE_SHA256=2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
Running VMs: []
hidden_api_policy = null
```

## Next boundary

The raw transport itself is no longer the immediate uncertainty.  Before any
new runtime, perform a bounded read-only audit of the precise Windows ARM64
BCD semantics for `{default}.bootdebug`, `{default}.debug`, the inherited
serial debugger settings, and the phase where each is expected to answer the
host's initial `0x69` synchronization.  The audit must decide whether this
absence is expected before loader/kernel KD initialization or is evidence of
a remaining transport/configuration mismatch.  No media changes are justified
until that interpretation is concrete.


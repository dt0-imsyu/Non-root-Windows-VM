# Product app-owned KD: `IMAGE_AUDIT` gate control — 2026-09-09

## Scope

One separately authorized product-equivalent KD control retained the exact
existing BCD+r11 bundle and released no KD bytes before the raw serial marker
`IMAGE_AUDIT start enter`.  It did not rebuild firmware, Android, WIM, BCD,
or signed Windows binaries.

Before the app-private transaction, the immutable external image was exactly
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7` and
the merged bundle was exactly
`4F2EA0AE40E6467608EA753E1368EC3F97C03A4C11DA9B2A17782D62B93742E6`.

## Gate result

The bridge was authenticated and its raw receiver found the full marker.  This
is certain because execution reached `NetworkStream.ReadTimeout = 0` only
after the complete ASCII needle matched.  The raw capture is:

```text
build-logs/product-kd-image-audit-gated-runtime-20260909-175621/raw-guest-to-kd.bin
length = 1,290,825 bytes
```

The host then threw:

```text
Timeout can be only be set to 'System.Threading.Timeout.Infinite'
or a value > 0.
```

This is a host-side .NET API error, not guest output, firmware, BCD, or
Windows behaviour.  It happened before `kd.exe` was created, before the named
pipe was opened, and before any host-to-guest debugger byte could be sent.

```text
IMAGE_AUDIT_GATE_OBSERVED       = PASS
GATED_NO_PREBOOT_KD_TX          = PASS
KD_RELEASE                      = NOT_COMPLETED (host API error)
WINDOWS_KD_HANDSHAKE            = NOT_TESTED
```

`run-product-kd-raw-bridge.ps1` now uses the documented
`System.Threading.Timeout.Infinite` value after a successful marker match.
The script parses successfully; this fix has not been runtime-tested.

## Cleanup

The script's `finally` path force-stopped only `com.example.winavf`, ran
transactional rollback, and restored hidden API policy.  Direct post-run audit
confirmed:

```text
RESULT=PASS
BASELINE_SHA256=2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
Running VMs: []
hidden_api_policy = null
```

## Next action

Do not repeat automatically.  The next separately authorized run may use the
same exact merged patch and the same `IMAGE_AUDIT start enter` gate with the
fixed host script.  It is the first configuration that both avoids U-Boot
input and has a proven observable release marker.


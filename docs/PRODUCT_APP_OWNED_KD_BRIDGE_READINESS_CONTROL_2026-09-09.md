# Product KD bridge readiness control — 2026-09-09

## Result

The fixed `IMAGE_AUDIT`-gate bridge was invoked once, but it did not create a
VM or apply its app-private patch.  The host connected to the local `adb
forward` endpoint immediately after launching the Android Activity and got an
EOF before the expected bridge greeting.

The device-side report still contained only:

```text
scope=APP_OWNED_PRODUCT_VM_RAW_KD_BRIDGE
listener=127.0.0.1:39100
state=LISTENING
```

Thus the Android listener was not yet ready when the host made its one client
connection.  The app never authenticated a token, never created the product
VM, and never called `applyStagedImagePatch`.  Its later rollback truthfully
reported `No active image patch exists to roll back`.

Independent post-control state:

```text
external baseline SHA = 2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7
Running VMs: []
hidden_api_policy = null
```

## Minimal host fix

`tools/product-kd/run-product-kd-raw-bridge.ps1` now polls the app's own
`product-kd-bridge-report.txt` until `state=LISTENING` appears, before making
the single localhost client connection.  This avoids using speculative TCP
connects against the one-accept Android listener.  It is host-only and does
not modify Android, firmware, BCD, WIM, or patch bytes.

The corrected PowerShell and embedded C# bridge code parse/compile.  No VM
rerun was made after this change.

```text
PRODUCT_KD_VM_CREATED             = NOT_REACHED
PRODUCT_KD_PATCH_APPLIED          = NOT_REACHED
IMAGE_AUDIT_GATE_RUNTIME          = NOT_REACHED
WINDOWS_KD_HANDSHAKE              = NOT_TESTED
```

Artifacts:
`build-logs/product-kd-image-audit-kd-runtime-20260909-180253/`.


# Host ADB execution blocker - 2026-09-09

## Result

The required read-only Android preflight could not be executed from the agent
sandbox. Direct process creation for the existing
`C:\Users\denis\AppData\Local\Android\Sdk\platform-tools\adb.exe` was denied by
the execution policy. Alternate shells and an elevation request were not used
as bypasses after the handoff explicitly identified this restriction.

This is classified as:

```text
HOST_ADB_EXECUTION_UNAVAILABLE_FROM_SANDBOX = BLOCKED
VM_RUNTIME_RESULT                         = NOT_RUN
```

No VM was started, no Android policy was changed, no image patch was pushed,
and no rollback was needed in this session.

## Prepared safe channel

`tools/product-kd/invoke-adb-allowlist.ps1` is a host-side executor intended to
run outside the agent sandbox. It exposes only the operations required by the
handoff, records JSONL operation results with stdout/stderr/exit code, accepts
only the audited combined patch SHA for `push`, accepts only `WinAVF-test.apk`
for install, and disallows policy-changing generic shell arguments. Its
`rollback` operation force-stops only `com.example.winavf`, requests the app's
transactional rollback, and then checks rollback report, image hash, VM list,
and hidden API policy.

Run the following read-only command on the Windows host, outside the sandbox,
before any runtime command:

```powershell
Set-Location 'C:\Users\denis\MainProjects\win11ontab\Non-root-Windows-VM'
.\tools\product-kd\invoke-adb-allowlist.ps1 -Operation baseline_check
```

The expected values remain the handoff reference: image SHA
`2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7`,
`Running VMs: []`, and `hidden_api_policy = null`. Only after those values are
returned should the exact one-run command in
`docs/NEXT_SESSION_HANDOFF_PRODUCT_KD_2026-09-09.md` be considered executable.

# Local artifact policy

The repository contains the scripts, source, reports, hashes and exact local
paths needed to reproduce each experiment. It intentionally does **not** put
raw VM images, firmware volumes, APKs, or `build-logs/` into ordinary Git.

Those generated artifacts total more than 2 GiB and include disk-derived
content. GitHub rejects individual blobs above its normal size limit and is
not an appropriate transport for private guest media.

## Retained locally

`build-logs/` remains the evidence store on the development workstation. Each
runtime report in `docs/` identifies the relevant artifact directory and
records immutable input and output SHA-256 values.

## Versioned in Git

- firmware, Android and guest-side source;
- builders, materializers, auditors and rollback scripts;
- runtime reports, evidence manifests, source-level reproducer descriptions;
- baseline/candidate/patch hashes and rollback verdicts.

## Sharing an evidence set

For a vendor escalation, create a small separate archive containing only the
specific raw serial log, the associated report, and a checksum manifest after
the recipient requests it. Never include a full Windows image or generic
build-log tree by default.

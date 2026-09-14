"""Create a disposable FAT32 UEFI boot volume for the QEMU contract probe.

This uses the installed pyfatfs library rather than custom FAT mutation.  The
result is a superfloppy-style FAT32 image used only by the isolated QEMU run.
"""
import argparse
import hashlib
from pathlib import Path

from pyfatfs.PyFat import PyFat
from pyfatfs.PyFatFS import PyFatFS


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--efi", required=True, type=Path)
    parser.add_argument("--image", required=True, type=Path)
    args = parser.parse_args()

    efi = args.efi.resolve()
    image = args.image.resolve()
    if not efi.is_file():
        raise SystemExit(f"missing EFI: {efi}")
    if image.exists():
        raise SystemExit(f"refusing to overwrite: {image}")

    # pyfatfs formats an existing block device/file rather than creating it.
    with image.open("xb") as raw:
        raw.truncate(128 * 1024 * 1024)

    fat = PyFat()
    fat.mkfs(str(image), fat_type=PyFat.FAT_TYPE_FAT32, size=128 * 1024 * 1024, label="QCP")
    fat.close()

    volume = PyFatFS(str(image), preserve_case=True)
    try:
        volume.makedirs("/EFI/BOOT", recreate=True)
        with efi.open("rb") as source, volume.openbin("/EFI/BOOT/BOOTAA64.EFI", "w") as target:
            while chunk := source.read(1024 * 1024):
                target.write(chunk)
        with volume.openbin("/EFI/BOOT/BOOTAA64.EFI", "r") as copied:
            copied_hash = hashlib.sha256(copied.read()).hexdigest().upper()
    finally:
        volume.close()

    expected_hash = sha256(efi)
    if copied_hash != expected_hash:
        raise SystemExit("EFI copy hash mismatch")
    print("RESULT=PASS")
    print(f"FAT_IMAGE={image}")
    print(f"FAT_BYTES={image.stat().st_size}")
    print(f"FAT_SHA256={sha256(image)}")
    print(f"EFI_SHA256={expected_hash}")
    print("LAYOUT=FAT32 superfloppy /EFI/BOOT/BOOTAA64.EFI")


if __name__ == "__main__":
    main()

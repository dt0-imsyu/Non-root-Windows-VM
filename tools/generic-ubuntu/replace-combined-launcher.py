"""Copy a disposable combined disk and replace only its FAT EFI launcher."""
import argparse
import hashlib
from pathlib import Path
import shutil

from pyfatfs.PyFatFS import PyFatFS

OFFSET = 1024 * 1024
ORIGINAL = "7F388FCB12598FAF5D8D0265BF41BD222328820064C3F7C9278B7979E2F0F740"


def digest(source):
    value = hashlib.sha256()
    for block in iter(lambda: source.read(1024 * 1024), b""):
        value.update(block)
    return value.hexdigest().upper()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--launcher", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("refusing to overwrite output")
    if args.launcher.stat().st_size != 20480:
        raise SystemExit("unexpected launcher size")
    shutil.copyfile(args.input, args.output)
    volume = PyFatFS(str(args.output), offset=OFFSET, preserve_case=True)
    try:
        path = "/EFI/BOOT/BOOTAA64.EFI"
        with volume.openbin(path, "r") as existing:
            if digest(existing) != ORIGINAL:
                raise RuntimeError("existing EFI launcher SHA mismatch")
        with args.launcher.open("rb") as new, volume.openbin(path, "r+") as target:
            shutil.copyfileobj(new, target, 1024 * 1024)
        with volume.openbin(path, "r") as installed, args.launcher.open("rb") as new:
            if digest(installed) != digest(new):
                raise RuntimeError("updated EFI launcher SHA mismatch")
    finally:
        volume.close()
    with args.output.open("rb") as source:
        print(f"OUTPUT_SHA256={digest(source)}")
    print(f"LAUNCHER_SHA256={hashlib.sha256(args.launcher.read_bytes()).hexdigest().upper()}")
    print("RESULT=PASS")


if __name__ == "__main__":
    main()

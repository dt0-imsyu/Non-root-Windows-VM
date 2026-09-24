"""Stage a stock Ubuntu ISO on a separate GPT platform ESP."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import uuid
import zlib

from pyfatfs.PyFat import PyFat
from pyfatfs.PyFatFS import PyFatFS

ISO_HASH = "2BE09CA883921BFF6D8E6B0BFBAFD13E32436553B7086F33BCE3A4C5BAD8BD14"
IMAGE_SIZE = 128 * 1024 * 1024
FAT_SIZE = 126 * 1024 * 1024
START_LBA = 2048
SECTOR_SIZE = 512


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def copy_into(fs, source, destination):
    with source.open("rb") as reader, fs.openbin(destination, "w") as writer:
        shutil.copyfileobj(reader, writer, 1024 * 1024)


def extract(bsdtar, iso, member, output):
    with output.open("xb") as target:
        subprocess.run([str(bsdtar), "-xOf", str(iso), member],
                       stdout=target, check=True)
    if not output.stat().st_size:
        raise RuntimeError(f"empty ISO member: {member}")


def gpt():
    total_lbas = IMAGE_SIZE // SECTOR_SIZE
    partition_lbas = FAT_SIZE // SECTOR_SIZE
    entries = bytearray(128 * 128)
    esp_type = uuid.UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b").bytes_le
    part_id = uuid.uuid5(uuid.NAMESPACE_URL, "uavf-platform-partition").bytes_le
    disk_id = uuid.uuid5(uuid.NAMESPACE_URL, "uavf-platform-disk").bytes_le
    struct.pack_into("<16s16sQQQ", entries, 0, esp_type, part_id,
                     START_LBA, START_LBA + partition_lbas - 1, 0)
    name = "U-AVF Platform".encode("utf-16le")
    entries[56:56 + len(name)] = name
    entries_crc = zlib.crc32(entries)

    def header(current, alternate, entry_lba):
        data = bytearray(SECTOR_SIZE)
        struct.pack_into("<8sIIIIQQQQ16sQIII", data, 0,
                         b"EFI PART", 0x10000, 92, 0, 0, current, alternate,
                         34, total_lbas - 34, disk_id, entry_lba,
                         128, 128, entries_crc)
        struct.pack_into("<I", data, 16, zlib.crc32(data[:92]))
        return data

    mbr = bytearray(SECTOR_SIZE)
    struct.pack_into("<B3sB3sII", mbr, 446, 0, b"\0\2\0", 0xEE,
                     b"\xff\xff\xff", 1, total_lbas - 1)
    mbr[510:512] = b"\x55\xaa"
    return mbr, header(1, total_lbas - 1, 2), header(total_lbas - 1, 1, total_lbas - 33), entries


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--iso", required=True, type=Path)
    parser.add_argument("--launcher", required=True, type=Path)
    parser.add_argument("--firmware", required=True, type=Path)
    parser.add_argument("--bsdtar", required=True, type=Path)
    parser.add_argument("--esp", required=True, type=Path)
    args = parser.parse_args()
    iso, launcher, firmware, bsdtar, esp = (
        path.resolve() for path in
        (args.iso, args.launcher, args.firmware, args.bsdtar, args.esp)
    )
    for path in (iso, launcher, firmware, bsdtar):
        if not path.is_file():
            raise SystemExit(f"missing input: {path}")
    if sha256(iso) != ISO_HASH:
        raise SystemExit("stock ISO SHA-256 mismatch")
    if firmware.stat().st_size != 2 * 1024 * 1024:
        raise SystemExit("unexpected EDK2 FD size")
    if esp.exists():
        raise SystemExit(f"refusing to overwrite: {esp}")
    esp.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="uavf-platform-") as scratch:
        work = Path(scratch)
        kernel, initrd, fat_path = (work / name for name in
                                    ("vmlinuz", "initrd", "platform.fat"))
        extract(bsdtar, iso, "casper/vmlinuz", kernel)
        extract(bsdtar, iso, "casper/initrd", initrd)
        fat_path.touch()
        fat = PyFat()
        fat.mkfs(str(fat_path), fat_type=PyFat.FAT_TYPE_FAT32,
                 size=FAT_SIZE, label="UAVFESP")
        fat.close()
        volume = PyFatFS(str(fat_path), preserve_case=True)
        try:
            for folder in ("/EFI/BOOT", "/EFI/EDK2", "/CASPER"):
                volume.makedirs(folder, recreate=True)
            copy_into(volume, launcher, "/EFI/BOOT/BOOTAA64.EFI")
            copy_into(volume, firmware, "/EFI/EDK2/QEMU_EFI.fd")
            copy_into(volume, kernel, "/CASPER/VMLINUZ")
            copy_into(volume, initrd, "/CASPER/INITRD")
        finally:
            volume.close()
        mbr, primary, backup, entries = gpt()
        try:
            with esp.open("xb") as raw:
                raw.truncate(IMAGE_SIZE)
                raw.write(mbr)
                raw.write(primary)
                raw.write(entries)
                raw.seek(START_LBA * SECTOR_SIZE)
                with fat_path.open("rb") as fat_source:
                    shutil.copyfileobj(fat_source, raw, 1024 * 1024)
                raw.seek(IMAGE_SIZE - 33 * SECTOR_SIZE)
                raw.write(entries)
                raw.write(backup)
                raw.flush()
                os.fsync(raw.fileno())
        except Exception:
            esp.unlink(missing_ok=True)
            raise
        for label, path in (("ISO", iso), ("LAUNCHER", launcher),
                            ("FIRMWARE", firmware), ("KERNEL", kernel),
                            ("INITRD", initrd), ("ESP", esp)):
            print(f"{label}_SHA256={sha256(path)}")
        print("RESULT=PASS")
        print("ISO_MUTATED=NO")
        print("ESP_LAYOUT=GPT/FAT32@LBA2048")


if __name__ == "__main__":
    main()

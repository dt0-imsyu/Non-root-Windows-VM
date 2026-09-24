"""Put the existing 128 MiB platform ESP and unmodified ISO on one virtio disk.

The stock ISO remains a separate source file.  Its bytes are copied verbatim
into an ISO9660 partition, avoiding the two-virtio-blk topology that stalled
the current GenieZone guest before /init.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import struct
import uuid
import zlib

SECTOR = 512
ALIGN = 2048
ESP_FIRST = 2048
ESP_SECTORS = 126 * 1024 * 1024 // SECTOR
ISO_FIRST = 128 * 1024 * 1024 // SECTOR
ISO_SHA256 = "2BE09CA883921BFF6D8E6B0BFBAFD13E32436553B7086F33BCE3A4C5BAD8BD14"


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest().upper()


def make_gpt(total_lbas, iso_sectors):
    entries = bytearray(128 * 128)
    esp_type = uuid.UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b").bytes_le
    linux_type = uuid.UUID("0fc63daf-8483-4772-8e79-3d69d8477de4").bytes_le
    disk_id = uuid.uuid5(uuid.NAMESPACE_URL, "uavf-generic-ubuntu-combined-disk").bytes_le
    for slot, part_type, first, count, key, name in (
        (0, esp_type, ESP_FIRST, ESP_SECTORS, "uavf-platform-partition", "U-AVF Platform"),
        (1, linux_type, ISO_FIRST, iso_sectors, "uavf-stock-ubuntu-iso-partition", "Ubuntu ISO9660"),
    ):
        offset = slot * 128
        part_id = uuid.uuid5(uuid.NAMESPACE_URL, key).bytes_le
        struct.pack_into("<16s16sQQQ", entries, offset, part_type, part_id,
                         first, first + count - 1, 0)
        encoded = name.encode("utf-16le")
        entries[offset + 56:offset + 56 + len(encoded)] = encoded
    crc = zlib.crc32(entries)

    def header(current, alternate, entries_lba):
        data = bytearray(SECTOR)
        struct.pack_into("<8sIIIIQQQQ16sQIII", data, 0,
                         b"EFI PART", 0x10000, 92, 0, 0, current, alternate,
                         34, total_lbas - 34, disk_id, entries_lba,
                         128, 128, crc)
        struct.pack_into("<I", data, 16, zlib.crc32(data[:92]))
        return data

    mbr = bytearray(SECTOR)
    struct.pack_into("<B3sB3sII", mbr, 446, 0, b"\0\2\0", 0xEE,
                     b"\xff\xff\xff", 1, min(total_lbas - 1, 0xffffffff))
    mbr[510:512] = b"\x55\xaa"
    return mbr, header(1, total_lbas - 1, 2), header(total_lbas - 1, 1, total_lbas - 33), entries


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", required=True, type=Path)
    parser.add_argument("--iso", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    platform, iso, output = (path.resolve() for path in (args.platform, args.iso, args.output))
    if platform.stat().st_size != 128 * 1024 * 1024:
        raise SystemExit("platform disk size mismatch")
    if iso.stat().st_size % SECTOR or digest(iso) != ISO_SHA256:
        raise SystemExit("stock ISO size/hash mismatch")
    if output.exists():
        raise SystemExit(f"refusing to overwrite: {output}")
    iso_sectors = iso.stat().st_size // SECTOR
    total_lbas = ((ISO_FIRST + iso_sectors + 34 + ALIGN - 1) // ALIGN) * ALIGN
    mbr, primary, backup, entries = make_gpt(total_lbas, iso_sectors)
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        with platform.open("rb") as source, iso.open("rb") as stock, output.open("xb") as target:
            target.truncate(total_lbas * SECTOR)
            target.write(mbr)
            target.write(primary)
            target.write(entries)
            source.seek(ESP_FIRST * SECTOR)
            target.seek(ESP_FIRST * SECTOR)
            remaining = ESP_SECTORS * SECTOR
            while remaining:
                block = source.read(min(1024 * 1024, remaining))
                if not block:
                    raise RuntimeError("truncated platform ESP partition")
                target.write(block)
                remaining -= len(block)
            target.seek(ISO_FIRST * SECTOR)
            shutil.copyfileobj(stock, target, 1024 * 1024)
            target.seek((total_lbas - 33) * SECTOR)
            target.write(entries)
            target.write(backup)
            target.flush()
            os.fsync(target.fileno())
    except Exception:
        output.unlink(missing_ok=True)
        raise
    print(f"RESULT=PASS\nOUTPUT={output}\nBYTES={output.stat().st_size}")
    print(f"OUTPUT_SHA256={digest(output)}")
    print(f"STOCK_ISO_SHA256={ISO_SHA256}\nISO_PARTITION_LBA={ISO_FIRST}")
    print(f"ISO_PARTITION_BYTES={iso.stat().st_size}\nESP_PARTITION_BYTES={ESP_SECTORS * SECTOR}")


if __name__ == "__main__":
    main()

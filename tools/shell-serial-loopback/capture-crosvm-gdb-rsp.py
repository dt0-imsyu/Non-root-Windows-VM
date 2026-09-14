#!/usr/bin/env python3
"""Bounded, read-only crosvm GDB Remote Serial Protocol capture.

The target starts halted.  We save the initial register packet, resume it,
interrupt it once after the supplied bound, then save the final state.  This
does not write guest memory or registers and intentionally sends no breakpoint
or single-step command.
"""
from __future__ import annotations

import argparse
import json
import socket
import time
from pathlib import Path


def checksum(payload: bytes) -> bytes:
    return f"{sum(payload) & 0xff:02x}".encode("ascii")


class Rsp:
    def __init__(self, sock: socket.socket, transcript: Path):
        self.sock = sock
        self.sock.settimeout(15)
        self.log = transcript.open("wb")

    def close(self) -> None:
        self.log.close()
        self.sock.close()

    def recv_byte(self) -> bytes:
        data = self.sock.recv(1)
        if not data:
            raise ConnectionError("GDB peer closed")
        self.log.write(b"RX " + data.hex().encode() + b"\n")
        self.log.flush()
        return data

    def send_raw(self, data: bytes) -> None:
        self.sock.sendall(data)
        self.log.write(b"TX " + data.hex().encode() + b"\n")
        self.log.flush()

    def recv_packet(self) -> bytes:
        while True:
            start = self.recv_byte()
            if start == b"$":
                break
            if start in (b"+", b"-"):
                continue
        payload = bytearray()
        while True:
            part = self.recv_byte()
            if part == b"#":
                break
            payload.extend(part)
        received = self.recv_byte() + self.recv_byte()
        if received.lower() != checksum(bytes(payload)):
            self.send_raw(b"-")
            raise ValueError("bad GDB packet checksum")
        self.send_raw(b"+")
        return bytes(payload)

    def request(self, payload: bytes) -> bytes:
        packet = b"$" + payload + b"#" + checksum(payload)
        self.send_raw(packet)
        while True:
            ack = self.recv_byte()
            if ack == b"+":
                return self.recv_packet()
            if ack == b"-":
                self.send_raw(packet)


def aarch64_summary(regs: bytes) -> dict[str, str | int | None]:
    result: dict[str, str | int | None] = {"register_packet_bytes": len(regs)}
    # Standard AArch64 GDB ordering is x0..x30, sp, pc, cpsr, each 64-bit
    # little-endian except cpsr. Preserve raw data even if target XML differs.
    if len(regs) >= 33 * 8:
        result["sp"] = f"0x{int.from_bytes(regs[31*8:32*8], 'little'):016X}"
        result["pc"] = f"0x{int.from_bytes(regs[32*8:33*8], 'little'):016X}"
    else:
        result["sp"] = None
        result["pc"] = None
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=4567)
    parser.add_argument("--run-seconds", type=int, default=85)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    rsp = Rsp(socket.create_connection((args.host, args.port), timeout=20), args.output / "gdb-rsp-wire.log")
    try:
        supported = rsp.request(b"qSupported:multiprocess+")
        target_xml = rsp.request(b"qXfer:features:read:target.xml:0,fff")
        initial_stop = rsp.request(b"?")
        initial_regs = rsp.request(b"g")
        rsp.send_raw(b"$c#63")
        # c is acknowledged, but has no reply until the later interrupt.
        while rsp.recv_byte() != b"+":
            pass
        time.sleep(args.run_seconds)
        rsp.send_raw(b"\x03")
        final_stop = rsp.recv_packet()
        final_regs = rsp.request(b"g")
        try:
            rsp.request(b"D")
        except Exception:
            pass
    finally:
        rsp.close()

    (args.output / "initial-registers.hex").write_text(initial_regs.hex() + "\n", encoding="ascii")
    (args.output / "final-registers.hex").write_text(final_regs.hex() + "\n", encoding="ascii")
    (args.output / "target.xml.reply.txt").write_bytes(target_xml)
    summary = {
        "qSupported": supported.decode("ascii", "replace"),
        "initial_stop": initial_stop.decode("ascii", "replace"),
        "final_stop": final_stop.decode("ascii", "replace"),
        "initial": aarch64_summary(initial_regs),
        "final": aarch64_summary(final_regs),
        "run_seconds": args.run_seconds,
        "guest_writes": False,
    }
    (args.output / "gdb-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

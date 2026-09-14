# Console frame transport design — 2026-09-05

The first graphics transport will use the already app-readable AVF
`console_out` pipe. It is intentionally independent of the hidden Samsung
display Binder and does not alter the Windows baseline.

## Protocol

Each record starts with a 28-byte little-endian header:

```text
magic=0x46564157 ("WAVF")
version:u8=1, type:u8 (1 keyframe, 2 tile update), flags:u8 (bit 0=zlib), reserved:u8=0
width:u16, height:u16, sequence:u32, payload_length:u32, crc32(payload):u32, reserved:u32=0
```

Keyframes contain BGRA8888 pixels. Tile records contain repeated
`x:u16,y:u16,w:u16,h:u16,length:u32,data`; a tile may be raw BGRA or zlib
compressed. The decoder bounds dimensions, payload, tile coordinates, and
decompression output before touching the frame buffer and resynchronizes after
serial noise or a bad CRC.

## Throughput targets

At 1280x800, a raw frame is 4,096,000 bytes. Raw 30 FPS would require about
117 MiB/s before protocol overhead, so it is rejected as a design target.
The intended schedule is one keyframe at start and then dirty tiles. Installation
uses a 10 FPS cap; interactive mode requests 30 FPS but sends only changed tiles.
For example, 10% dirty area at 1280x800 is about 12 MiB/s uncompressed and is
usually reducible with zlib because setup screens have large flat regions.

The Android decoder is implemented in
`android-app/src/com/example/winavf/ConsoleFrameDecoder.java`. Firmware
encoder and SurfaceView presentation are separate steps so the protocol can be
tested with synthetic streams before any tablet runtime patch.


package com.example.winavf;

import java.io.ByteArrayOutputStream;
import java.util.zip.CRC32;
import java.util.zip.DataFormatException;
import java.util.zip.Inflater;

/**
 * Decoder for the bounded GOP/console transport. The stream may contain normal
 * serial text; the decoder scans for WAVF records and resynchronizes after
 * malformed input. Pixels are BGRA8888, stored row-major in the frame buffer.
 */
final class ConsoleFrameDecoder {
    static final int MAGIC = 0x46564157; // bytes: W A V F
    static final int VERSION = 1;
    static final int TYPE_KEYFRAME = 1;
    static final int TYPE_TILES = 2;
    static final int FLAG_DEFLATE = 1;
    static final int HEADER_SIZE = 28;
    static final int MAX_FRAME_BYTES = 16 * 1024 * 1024;
    static final int MAX_PAYLOAD_BYTES = 4 * 1024 * 1024;

    interface Listener {
        void onFrame(Frame frame);
        void onProtocolError(String message);
    }

    static final class Frame {
        final int width;
        final int height;
        final int sequence;
        final byte[] bgra;

        Frame(int width, int height, int sequence, byte[] bgra) {
            this.width = width;
            this.height = height;
            this.sequence = sequence;
            this.bgra = bgra;
        }
    }

    private final Listener listener;
    private final ByteArrayOutputStream pending = new ByteArrayOutputStream();
    private byte[] frame;
    private int frameWidth;
    private int frameHeight;

    ConsoleFrameDecoder(Listener listener) {
        this.listener = listener;
    }

    synchronized void feed(byte[] bytes, int offset, int length) {
        if (length <= 0) return;
        pending.write(bytes, offset, length);
        parse();
    }

    private void parse() {
        byte[] data = pending.toByteArray();
        int cursor = 0;
        while (data.length - cursor >= HEADER_SIZE) {
            int magic = le32(data, cursor);
            if (magic != MAGIC) {
                cursor++;
                continue;
            }
            int version = data[cursor + 4] & 0xff;
            int type = data[cursor + 5] & 0xff;
            int flags = data[cursor + 6] & 0xff;
            int width = le16(data, cursor + 8);
            int height = le16(data, cursor + 10);
            int sequence = le32(data, cursor + 12);
            int payloadLength = le32(data, cursor + 16);
            int expectedCrc = le32(data, cursor + 20);
            int reserved = le32(data, cursor + 24);
            if (version != VERSION || reserved != 0 || width == 0 || height == 0
                    || width > 4096 || height > 4096 || payloadLength < 0
                    || payloadLength > MAX_PAYLOAD_BYTES) {
                error("invalid header");
                cursor++;
                continue;
            }
            long frameBytes = (long) width * height * 4L;
            if (frameBytes > MAX_FRAME_BYTES) {
                error("frame too large");
                cursor++;
                continue;
            }
            if (data.length - cursor < HEADER_SIZE + payloadLength) break;
            byte[] payload = new byte[payloadLength];
            System.arraycopy(data, cursor + HEADER_SIZE, payload, 0, payloadLength);
            CRC32 crc = new CRC32();
            crc.update(payload);
            if ((int) crc.getValue() != expectedCrc) {
                error("CRC mismatch");
                cursor++;
                continue;
            }
            if ((flags & ~FLAG_DEFLATE) != 0) {
                error("unknown flags");
                cursor += HEADER_SIZE + payloadLength;
                continue;
            }
            byte[] decoded = (flags & FLAG_DEFLATE) != 0 ? inflate(payload, (int) frameBytes) : payload;
            if (decoded == null) {
                cursor += HEADER_SIZE + payloadLength;
                continue;
            }
            if (type == TYPE_KEYFRAME) {
                if (decoded.length != frameBytes) {
                    error("keyframe size mismatch");
                } else {
                    frameWidth = width;
                    frameHeight = height;
                    frame = decoded;
                    emit(sequence);
                }
            } else if (type == TYPE_TILES) {
                if (frame == null || frameWidth != width || frameHeight != height) {
                    error("tile frame without matching keyframe");
                } else if (applyTiles(decoded)) {
                    emit(sequence);
                }
            } else {
                error("unknown record type");
            }
            cursor += HEADER_SIZE + payloadLength;
        }
        pending.reset();
        if (data.length - cursor > HEADER_SIZE - 1) {
            pending.write(data, cursor, data.length - cursor);
        } else if (data.length > cursor) {
            pending.write(data, cursor, data.length - cursor);
        }
    }

    private boolean applyTiles(byte[] payload) {
        int cursor = 0;
        while (cursor < payload.length) {
            if (payload.length - cursor < 12) {
                error("truncated tile header");
                return false;
            }
            int x = le16(payload, cursor);
            int y = le16(payload, cursor + 2);
            int width = le16(payload, cursor + 4);
            int height = le16(payload, cursor + 6);
            int length = le32(payload, cursor + 8);
            cursor += 12;
            long rawLength = (long) width * height * 4L;
            if (width == 0 || height == 0 || x + width > frameWidth || y + height > frameHeight
                    || length < 0 || rawLength > MAX_FRAME_BYTES || length > payload.length - cursor) {
                error("invalid tile");
                return false;
            }
            byte[] tile = new byte[length];
            System.arraycopy(payload, cursor, tile, 0, length);
            cursor += length;
            byte[] raw = tile;
            if (raw.length != rawLength) {
                raw = inflate(tile, (int) rawLength);
                if (raw == null) return false;
            }
            for (int row = 0; row < height; row++) {
                int source = row * width * 4;
                int target = ((y + row) * frameWidth + x) * 4;
                System.arraycopy(raw, source, frame, target, width * 4);
            }
        }
        return cursor == payload.length;
    }

    private byte[] inflate(byte[] compressed, int expectedLength) {
        Inflater inflater = new Inflater();
        inflater.setInput(compressed);
        byte[] output = new byte[expectedLength];
        try {
            int length = inflater.inflate(output);
            if (!inflater.finished() || length != expectedLength) {
                error("deflate size mismatch");
                return null;
            }
            return output;
        } catch (DataFormatException error) {
            error("invalid deflate payload");
            return null;
        } finally {
            inflater.end();
        }
    }

    private void emit(int sequence) {
        byte[] copy = frame.clone();
        listener.onFrame(new Frame(frameWidth, frameHeight, sequence, copy));
    }

    private void error(String message) {
        listener.onProtocolError(message);
    }

    private static int le16(byte[] data, int offset) {
        return (data[offset] & 0xff) | ((data[offset + 1] & 0xff) << 8);
    }

    private static int le32(byte[] data, int offset) {
        return (data[offset] & 0xff) | ((data[offset + 1] & 0xff) << 8)
                | ((data[offset + 2] & 0xff) << 16) | ((data[offset + 3] & 0xff) << 24);
    }
}

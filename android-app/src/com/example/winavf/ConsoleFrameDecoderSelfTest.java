package com.example.winavf;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.zip.CRC32;

/** Host-side smoke test: keyframe, serial noise, and one tile update. */
public final class ConsoleFrameDecoderSelfTest {
    public static void main(String[] args) {
        final int[] frames = {0};
        ConsoleFrameDecoder decoder = new ConsoleFrameDecoder(new ConsoleFrameDecoder.Listener() {
            @Override public void onFrame(ConsoleFrameDecoder.Frame frame) {
                frames[0]++;
                if (frame.sequence == 1 && (frame.bgra[0] & 0xff) != 0x11) throw new AssertionError("keyframe");
                if (frame.sequence == 2 && (frame.bgra[4] & 0xff) != 0x33) throw new AssertionError("tile");
            }
            @Override public void onProtocolError(String message) { throw new AssertionError(message); }
        });
        byte[] key = new byte[2 * 1 * 4];
        key[0] = 0x11;
        decoder.feed(record(1, 2, 1, key), 0, record(1, 2, 1, key).length);
        byte[] tile = new byte[12 + 4];
        put16(tile, 0, 1); put16(tile, 2, 0); put16(tile, 4, 1); put16(tile, 6, 1); put32(tile, 8, 4);
        tile[12] = 0x33;
        byte[] update = record(2, 2, 2, tile);
        byte[] noisy = new byte[3 + update.length];
        noisy[0] = 'x'; noisy[1] = '\n'; noisy[2] = 0;
        System.arraycopy(update, 0, noisy, 3, update.length);
        decoder.feed(noisy, 0, noisy.length);
        if (frames[0] != 2) throw new AssertionError("frame count=" + frames[0]);
        System.out.println("ConsoleFrameDecoderSelfTest PASS frames=" + frames[0]);
    }

    private static byte[] record(int type, int width, int sequence, byte[] payload) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ByteBuffer h = ByteBuffer.allocate(28).order(ByteOrder.LITTLE_ENDIAN);
        h.putInt(ConsoleFrameDecoder.MAGIC).put((byte) 1).put((byte) type).put((byte) 0).put((byte) 0);
        h.putShort((short) width).putShort((short) 1).putInt(sequence).putInt(payload.length);
        CRC32 crc = new CRC32(); crc.update(payload);
        h.putInt((int) crc.getValue()).putInt(0);
        out.writeBytes(h.array()); out.writeBytes(payload); return out.toByteArray();
    }

    private static void put16(byte[] b, int o, int v) { b[o] = (byte) v; b[o + 1] = (byte) (v >>> 8); }
    private static void put32(byte[] b, int o, int v) { for (int i = 0; i < 4; i++) b[o + i] = (byte) (v >>> (8 * i)); }
}

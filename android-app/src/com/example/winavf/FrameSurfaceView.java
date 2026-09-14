package com.example.winavf;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.view.View;

/** App-owned presentation surface for decoded guest frames. */
final class FrameSurfaceView extends View {
    private Bitmap bitmap;
    private int[] argb;

    FrameSurfaceView(Context context) {
        super(context);
        setBackgroundColor(Color.BLACK);
    }

    synchronized void present(ConsoleFrameDecoder.Frame frame) {
        if (bitmap == null || bitmap.getWidth() != frame.width || bitmap.getHeight() != frame.height) {
            bitmap = Bitmap.createBitmap(frame.width, frame.height, Bitmap.Config.ARGB_8888);
            argb = new int[frame.width * frame.height];
        }
        byte[] bgra = frame.bgra;
        for (int i = 0, p = 0; i < argb.length; i++, p += 4) {
            int b = bgra[p] & 0xff;
            int g = bgra[p + 1] & 0xff;
            int r = bgra[p + 2] & 0xff;
            int a = bgra[p + 3] & 0xff;
            argb[i] = (a << 24) | (r << 16) | (g << 8) | b;
        }
        bitmap.setPixels(argb, 0, frame.width, 0, 0, frame.width, frame.height);
        postInvalidateOnAnimation();
    }

    @Override protected synchronized void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (bitmap == null) return;
        float scale = Math.min(getWidth() / (float) bitmap.getWidth(), getHeight() / (float) bitmap.getHeight());
        float left = (getWidth() - bitmap.getWidth() * scale) / 2f;
        float top = (getHeight() - bitmap.getHeight() * scale) / 2f;
        canvas.drawBitmap(bitmap, null,
                new android.graphics.RectF(left, top, left + bitmap.getWidth() * scale,
                        top + bitmap.getHeight() * scale), null);
    }
}

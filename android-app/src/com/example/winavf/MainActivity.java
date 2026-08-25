package com.example.winavf;

import android.app.Activity;
import android.system.Os;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.io.RandomAccessFile;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.lang.reflect.Field;
import java.lang.reflect.Constructor;
import java.util.Arrays;
import java.util.concurrent.Executor;
import java.util.concurrent.ForkJoinPool;

/** Minimal custom-AVF launcher. Hidden AVF classes are resolved at runtime. */
public final class MainActivity extends Activity {
    private static final String VM_NAME = "winavf-winpe-userland-r11";
    private static final long WINDOWS_TARGET_SIZE = 64L * 1024L * 1024L * 1024L;
    private static final String HEADLESS_SETUP_MEDIA_NAME = "win11-headless-installer-10g.img";
    private static final long HEADLESS_SETUP_MEDIA_MIN_SIZE = 7L * 1024L * 1024L * 1024L;
    private static final String HEADLESS_SETUP_MEDIA_REVISION = "r3-efi-gpt";
    private static final String HEADLESS_BOOT_MEDIA_NAME = "win11-winpe-userland-r4.img";
    private static final long HEADLESS_BOOT_MEDIA_SIZE = 9_126_805_504L;
    private TextView status;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        Button start = new Button(this);
        start.setText("Start kernel-first loader test");
        start.setOnClickListener(v -> new Thread(this::startTest, "WinAVF-start").start());
        status = new TextView(this);
        status.setText("Ready. Headless Windows ARM64 installer: serial/EDK2/disks only; no Android guest surface.");
        ScrollView scroll = new ScrollView(this);
        scroll.addView(status);
        page.addView(start);
        page.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(page);
        if (getIntent().getBooleanExtra("start", false)) {
            new Thread(this::startTest, "WinAVF-start").start();
        }
        if (getIntent().getBooleanExtra("audit", false)) {
            new Thread(this::auditVirtualizationCapabilities, "WinAVF-audit").start();
        }
    }

    /** Records only display/input-related members present in this device's runtime. */
    private void auditVirtualizationCapabilities() {
        File report = new File(getExternalFilesDir(null), "avf-capability-audit.txt");
        String[] classes = {
                "android.system.virtualmachine.VirtualMachineManager",
                "android.system.virtualmachine.VirtualMachine",
                "android.system.virtualmachine.VirtualMachineConfig",
                "android.system.virtualmachine.VirtualMachineConfig$Builder",
                "android.system.virtualmachine.VirtualMachineCustomImageConfig",
                "android.system.virtualmachine.VirtualMachineCustomImageConfig$Builder",
                "android.system.virtualmachine.VirtualMachineCustomImageConfig$DisplayConfig",
                "android.system.virtualmachine.VirtualMachineCustomImageConfig$DisplayConfig$Builder",
                "android.system.virtualmachine.VirtualMachineCustomImageConfig$GpuConfig",
                "android.system.virtualmachine.VirtualMachineCustomImageConfig$GpuConfig$Builder",
                "android.system.virtualmachine.VirtualMachineDescriptor",
                "android.system.virtualmachine.VirtualMachineCallback"
        };
        try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
            out.println("fingerprint=" + android.os.Build.FINGERPRINT);
            out.println("sdk=" + android.os.Build.VERSION.SDK_INT);
            for (String name : classes) {
                try {
                    Class<?> type = Class.forName(name);
                    out.println("CLASS " + name + " AVAILABLE");
                    Constructor<?>[] constructors = type.getDeclaredConstructors();
                    Arrays.sort(constructors, (a, b) -> a.toString().compareTo(b.toString()));
                    for (Constructor<?> constructor : constructors) out.println("  CONSTRUCTOR " + constructor);
                    Method[] methods = type.getDeclaredMethods();
                    Arrays.sort(methods, (a, b) -> a.toString().compareTo(b.toString()));
                    for (Method method : methods) {
                        String value = method.toString();
                        if (value.toLowerCase().matches(".*(display|graphics|gpu|surface|console|input|keyboard|mouse|touch|virtio|socket|vsock).*")) out.println("  METHOD " + value);
                    }
                    Field[] fields = type.getDeclaredFields();
                    Arrays.sort(fields, (a, b) -> a.toString().compareTo(b.toString()));
                    for (Field field : fields) {
                        String value = field.toString();
                        if (value.toLowerCase().matches(".*(display|graphics|gpu|surface|console|input|keyboard|mouse|touch|virtio|socket|vsock).*")) out.println("  FIELD " + value);
                    }
                } catch (Throwable error) {
                    out.println("CLASS " + name + " UNAVAILABLE " + rootMessage(error));
                }
            }
            String[] permissions = {
                    "android.permission.MANAGE_VIRTUAL_MACHINE",
                    "android.permission.USE_CUSTOM_VIRTUAL_MACHINE",
                    "android.permission.VIRTUAL_INPUT_DEVICE"
            };
            for (String permission : permissions) {
                android.content.pm.PermissionInfo info = getPackageManager().getPermissionInfo(permission, 0);
                out.println("PERMISSION " + permission + " check=" + checkSelfPermission(permission) + " protection=" + info.protectionLevel);
            }
        } catch (Throwable error) {
            show("AVF capability audit failed: " + rootMessage(error));
            return;
        }
        show("AVF capability audit saved to " + report.getAbsolutePath());
    }

    private void startTest() {
        try {
            show("Preparing app-private kernel-style loader…");
            File payload = new File(getFilesDir(), "payload");
            if (!payload.exists() && !payload.mkdirs()) throw new IllegalStateException("Cannot create payload directory");
            File kernel = copyAsset("u-boot-wrapper-v24.Image", new File(payload, "u-boot-wrapper-v24.Image"), -1L);
            File priorKernel = new File(payload, "u-boot-wrapper-start-marker.Image");
            if (priorKernel.isFile()) {
                File exported = new File(getExternalFilesDir(null), "initial-working-u-boot-wrapper.Image");
                try (InputStream in = new java.io.FileInputStream(priorKernel);
                     FileOutputStream out = new FileOutputStream(exported)) {
                    byte[] buffer = new byte[1024 * 1024];
                    for (int n; (n = in.read(buffer)) >= 0;) out.write(buffer, 0, n);
                }
            }
            // AVF accepts the app-internal copy as a read-only virtual disk.  The external
            // files directory is used only as the ADB transfer staging location.
            File bootMedia = new File(getExternalFilesDir(null), HEADLESS_BOOT_MEDIA_NAME);
            if (!bootMedia.isFile() || bootMedia.length() != HEADLESS_BOOT_MEDIA_SIZE) {
                throw new IllegalStateException("Missing compact headless boot medium: " + bootMedia);
            }
            File esp = copyFile(bootMedia, new File(payload, HEADLESS_BOOT_MEDIA_NAME), HEADLESS_BOOT_MEDIA_SIZE, true);
            show("Using the preserved Windows Boot Manager milestone medium only…");
            show("Creating custom AVF VM through Android API…");
            Object config = buildConfig(kernel, esp);
            Object manager = getSystemService((Class) Class.forName("android.system.virtualmachine.VirtualMachineManager"));
            try {
                Object prior = manager.getClass().getMethod("get", String.class).invoke(manager, VM_NAME);
                if (prior != null) manager.getClass().getMethod("delete", String.class).invoke(manager, VM_NAME);
            } catch (Exception ignored) { }
            Method create = manager.getClass().getMethod("create", String.class, config.getClass());
            Object vm = create.invoke(manager, VM_NAME, config);
            attachCallback(vm);
            InputStream console = (InputStream) vm.getClass().getMethod("getConsoleOutput").invoke(vm);
            startConsoleReader(console);
            vm.getClass().getMethod("run").invoke(vm);
            startWinpeMarkerReporter(esp);
            show("VM launched. Waiting for kernel-first serial output…");
        } catch (Throwable t) {
            show("FAILED: " + rootMessage(t));
        }
    }

    /** Stops autoboot and lists discovered bootflows; this is a read-only transport probe. */
    private void runBootflowProbe(Object vm) {
        new Thread(() -> {
            try {
                Thread.sleep(350);
                OutputStream input = (OutputStream) vm.getClass().getMethod("getConsoleInput").invoke(vm);
                input.write(' ');
                input.flush();
                Thread.sleep(1200);
                input.write("bootflow scan -l\n".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
                input.flush();
                show("U-Boot bootflow probe sent.");
            } catch (Throwable t) {
                show("Console-input probe unavailable: " + rootMessage(t));
            }
        }, "WinAVF-bootflow-probe").start();
    }

    /** Publishes a non-invasive progress marker for headless Setup activity. */
    private void startTargetUsageReporter(File target) {
        new Thread(() -> {
            File report = new File(getExternalFilesDir(null), "windows-target-usage.log");
            while (!Thread.currentThread().isInterrupted()) {
                try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                    long allocated = Os.stat(target.getAbsolutePath()).st_blocks * 512L;
                    out.println("logical=" + target.length());
                    out.println("allocated=" + allocated);
                    out.println("timestamp=" + System.currentTimeMillis());
                } catch (Throwable ignored) { return; }
                try { Thread.sleep(5000); } catch (InterruptedException ignored) { return; }
            }
        }, "WinAVF-target-usage").start();
    }

    private Object buildConfig(File kernel, File esp) throws Exception {
        Class<?> custom = Class.forName("android.system.virtualmachine.VirtualMachineCustomImageConfig");
        Class<?> customBuilder = Class.forName(custom.getName() + "$Builder");
        Object image = customBuilder.getConstructor().newInstance();
        call(image, "setName", String.class, VM_NAME);
        call(image, "setOsName", String.class, "winavf");
        call(image, "setKernelPath", String.class, kernel.getAbsolutePath());
        call(image, "useNetwork", boolean.class, false);
        call(image, "useAutoMemoryBalloon", boolean.class, true);
        Class<?> disk = Class.forName(custom.getName() + "$Disk");
        // Test 1 intentionally makes this single cloned installer disk writable
        // so WinPE can leave an in-band marker.  No second PCI device is added.
        Object writableEsp = disk.getMethod("RWDisk", String.class).invoke(null, esp.getAbsolutePath());
        call(image, "addDisk", disk, writableEsp);

        // GPU/display are enabled for the dynamic-boot-path proof.  The backend
        // remains platform-selected (Samsung chooses its supported gfxstream
        // path); no PCI address is supplied or assumed here.
        Class<?> displayBuilder = Class.forName(custom.getName() + "$DisplayConfig$Builder");
        Object display = displayBuilder.getConstructor().newInstance();
        call(display, "setWidth", int.class, 1280);
        call(display, "setHeight", int.class, 800);
        call(display, "setHorizontalDpi", int.class, 160);
        call(display, "setVerticalDpi", int.class, 160);
        call(display, "setRefreshRate", int.class, 60);
        Object displayConfig = call(display, "build");
        call(image, "setDisplayConfig", displayConfig.getClass(), displayConfig);
        Class<?> gpuBuilder = Class.forName(custom.getName() + "$GpuConfig$Builder");
        Object gpuConfig = call(gpuBuilder.getConstructor().newInstance(), "build");
        call(image, "setGpuConfig", gpuConfig.getClass(), gpuConfig);

        Object customConfig = call(image, "build");

        Class<?> vmConfig = Class.forName("android.system.virtualmachine.VirtualMachineConfig");
        Class<?> builder = Class.forName(vmConfig.getName() + "$Builder");
        Object config = builder.getConstructor(android.content.Context.class).newInstance(this);
        call(config, "setProtectedVm", boolean.class, false);
        call(config, "setMemoryBytes", long.class, 4L * 1024 * 1024 * 1024);
        call(config, "setCpuTopology", int.class, vmConfig.getField("CPU_TOPOLOGY_MATCH_HOST").getInt(null));
        call(config, "setDebugLevel", int.class, 1);
        call(config, "setConsoleInputDevice", String.class, "ttyS0");
        call(config, "setVmOutputCaptured", boolean.class, true);
        call(config, "setVmConsoleInputSupported", boolean.class, true);
        call(config, "setCustomImageConfig", custom, customConfig);
        return call(config, "build");
    }

    private void attachCallback(Object vm) throws Exception {
        Class<?> callback = Class.forName("android.system.virtualmachine.VirtualMachineCallback");
        Object proxy = Proxy.newProxyInstance(getClassLoader(), new Class<?>[] { callback }, (p, method, args) -> {
            if (method.getName().equals("onError") || method.getName().equals("onStopped")) show("VM " + method.getName() + ": " + java.util.Arrays.toString(args));
            return null;
        });
        vm.getClass().getMethod("setCallback", Executor.class, callback).invoke(vm, ForkJoinPool.commonPool(), proxy);
    }

    private void startConsoleReader(InputStream console) {
        new Thread(() -> {
            File serialLog = new File(getExternalFilesDir(null), "serial.log");
            show("Writing complete VM serial log to " + serialLog.getAbsolutePath());
            try (FileOutputStream rawLog = new FileOutputStream(serialLog, false)) {
                byte[] buffer = new byte[256];
                for (int n; (n = console.read(buffer)) >= 0;) {
                    rawLog.write(buffer, 0, n);
                    rawLog.flush();
                    String text = new String(buffer, 0, n, java.nio.charset.StandardCharsets.UTF_8);
                    // U-Boot emits many one-byte console writes.  Rendering each one on
                    // Android's UI thread starves the VM and truncates the useful EDK2 log.
                    if (text.indexOf('\n') >= 0) {
                        show("SERIAL: " + text.replace("\r", "").replace("\n", ""));
                    }
                }
            } catch (Throwable t) {
                show("Console closed: " + rootMessage(t));
            }
        }, "WinAVF-console").start();
    }

    /** Reads a marker written by WinPE from the FAT root; it never writes guest media. */
    private void startWinpeMarkerReporter(File disk) {
        new Thread(() -> {
            for (int attempt = 0; attempt < 360; ++attempt) {
                try {
                    String marker = readWinpeMarker(disk);
                    if (marker != null) {
                        File report = new File(getExternalFilesDir(null), "winpe-userland-marker.txt");
                        try (FileOutputStream out = new FileOutputStream(report, false)) {
                            out.write(marker.getBytes(java.nio.charset.StandardCharsets.US_ASCII));
                        }
                        show("WINPE_USERLAND marker found: " + marker.replace("\r", " ").replace("\n", " | "));
                        return;
                    }
                } catch (Throwable ignored) { }
                try { Thread.sleep(2000); } catch (InterruptedException ignored) { return; }
            }
        }, "WinAVF-winpe-marker").start();
    }

    private static int u16(byte[] b, int o) { return (b[o] & 255) | ((b[o + 1] & 255) << 8); }
    private static long u32(byte[] b, int o) { return ((long) u16(b, o)) | ((long) u16(b, o + 2) << 16); }

    private static String readWinpeMarker(File disk) throws Exception {
        final long partition = 1024L * 1024L;
        try (RandomAccessFile raw = new RandomAccessFile(disk, "r")) {
            byte[] bpb = new byte[512]; raw.seek(partition); raw.readFully(bpb);
            int bps = u16(bpb, 11), spc = bpb[13] & 255, reserved = u16(bpb, 14), fats = bpb[16] & 255;
            long fatSectors = u32(bpb, 36), root = u32(bpb, 44);
            long fat = partition + (long) reserved * bps;
            long data = partition + (long) (reserved + fats * fatSectors) * bps;
            int clusterBytes = bps * spc;
            long cluster = root;
            for (int guard = 0; guard < 1024 && cluster >= 2 && cluster < 0x0ffffff8L; ++guard) {
                byte[] directory = new byte[clusterBytes]; raw.seek(data + (cluster - 2) * clusterBytes); raw.readFully(directory);
                for (int off = 0; off + 32 <= directory.length; off += 32) {
                    if (directory[off] == 0) return null;
                    if ((directory[off] & 255) == 0xe5 || (directory[off + 11] & 255) == 0x0f) continue;
                    String name = new String(directory, off, 8, java.nio.charset.StandardCharsets.US_ASCII);
                    String ext = new String(directory, off + 8, 3, java.nio.charset.StandardCharsets.US_ASCII);
                    if (!ext.equals("TXT")) continue;
                    long first = ((long) u16(directory, off + 20) << 16) | u16(directory, off + 26);
                    int size = (int) u32(directory, off + 28);
                    if (size <= 0 || size > 4096) return null;
                    byte[] text = new byte[size]; int copied = 0;
                    while (first >= 2 && first < 0x0ffffff8L && copied < size) {
                        int take = Math.min(clusterBytes, size - copied);
                        raw.seek(data + (first - 2) * clusterBytes); raw.readFully(text, copied, take); copied += take;
                        byte[] next = new byte[4]; raw.seek(fat + first * 4); raw.readFully(next); first = u32(next, 0) & 0x0fffffffL;
                    }
                    String marker = new String(text, java.nio.charset.StandardCharsets.US_ASCII);
                    if (marker.contains("stage=WINPE_USERLAND_")) return marker;
                }
                byte[] next = new byte[4]; raw.seek(fat + cluster * 4); raw.readFully(next); cluster = u32(next, 0) & 0x0fffffffL;
            }
            return null;
        }
    }

    private File copyAsset(String asset, File destination, long expectedLength) throws Exception {
        if (destination.isFile() && (expectedLength < 0 || destination.length() == expectedLength)) return destination;
        try (InputStream in = getAssets().open(asset); FileOutputStream out = new FileOutputStream(destination)) {
            byte[] buffer = new byte[1024 * 1024];
            for (int n; (n = in.read(buffer)) >= 0;) out.write(buffer, 0, n);
        }
        return destination;
    }

    private File copyFile(File source, File destination, long expectedLength, boolean force) throws Exception {
        long requiredLength = expectedLength >= 0 ? expectedLength : source.length();
        if (!force && destination.isFile() && destination.length() == requiredLength) return destination;
        show("Copying Windows setup medium into app-private storage…");
        try (InputStream in = new java.io.FileInputStream(source); FileOutputStream out = new FileOutputStream(destination)) {
            byte[] buffer = new byte[1024 * 1024];
            for (int n; (n = in.read(buffer)) >= 0;) out.write(buffer, 0, n);
        }
        if (destination.length() != requiredLength) throw new IllegalStateException("Setup-medium copy has unexpected size");
        return destination;
    }

    private static String readText(File file) {
        try (InputStream in = new java.io.FileInputStream(file)) {
            byte[] bytes = new byte[(int) Math.min(file.length(), 128)];
            int count = in.read(bytes);
            return count > 0 ? new String(bytes, 0, count, java.nio.charset.StandardCharsets.US_ASCII) : "";
        } catch (Exception ignored) { return ""; }
    }

    private static void writeText(File file, String value) throws Exception {
        try (FileOutputStream out = new FileOutputStream(file, false)) {
            out.write(value.getBytes(java.nio.charset.StandardCharsets.US_ASCII));
        }
    }

    private File ensureSparseTarget(File target) throws Exception {
        if (!target.isFile() || target.length() != WINDOWS_TARGET_SIZE) {
            try (RandomAccessFile file = new RandomAccessFile(target, "rw")) {
                file.setLength(WINDOWS_TARGET_SIZE);
            }
        }
        long physical = Os.stat(target.getAbsolutePath()).st_blocks * 512L;
        show("Sparse Windows target: logical=" + target.length() + " physical=" + physical + " bytes");
        if (physical > 16L * 1024 * 1024) {
            throw new IllegalStateException("Sparse Windows target allocated too much: " + physical);
        }
        return target;
    }

    private static Object call(Object target, String name, Class<?> type, Object value) throws Exception {
        return target.getClass().getMethod(name, type).invoke(target, value);
    }
    private static Object call(Object target, String name) throws Exception { return target.getClass().getMethod(name).invoke(target); }
    private static Object newInstance(Class<?> type) throws Exception { return type.getConstructor().newInstance(); }
    private void show(String message) { runOnUiThread(() -> status.append("\n" + message)); }
    private static String rootMessage(Throwable error) {
        while (error.getCause() != null) error = error.getCause();
        return error.getClass().getSimpleName() + ": " + error.getMessage();
    }
}

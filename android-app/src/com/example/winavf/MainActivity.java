package com.example.winavf;

import android.app.Activity;
import android.graphics.Color;
import android.system.Os;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.FrameLayout;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;
import java.io.ByteArrayOutputStream;
import java.io.BufferedInputStream;
import java.io.FileOutputStream;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.io.RandomAccessFile;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.lang.reflect.Field;
import java.lang.reflect.Constructor;
import java.util.Arrays;
import java.util.concurrent.Executor;
import java.util.concurrent.ForkJoinPool;
import java.security.MessageDigest;
import java.util.zip.CRC32;

/** Minimal custom-AVF launcher. Hidden AVF classes are resolved at runtime. */
public final class MainActivity extends Activity {
    // Preserve the known-good launcher/media contract while adding only the
    // app-owned WAVF decoder surface.
    private static final String VM_NAME = "winavf-gop-ebs-r1";
    // This name is reserved for the hidden-API console-input capability probe.
    // It never starts a guest and is always deleted before the probe returns.
    private static final String CONSOLE_INPUT_PROBE_VM_NAME = "winavf-console-input-probe-20260909";
    private static final String CONSOLE_BINARY_ECHO_VM_NAME = "winavf-console-binary-echo-20260909";
    private static final byte[] CONSOLE_BINARY_ECHO_READY = "WINAVF_ECHO_READY\n".getBytes(java.nio.charset.StandardCharsets.US_ASCII);
    private static final int CONSOLE_BINARY_ECHO_BYTES = 4096;
    // localhost-only, diagnostic-only endpoint.  A fresh capability token is
    // supplied by the host bridge for every run; no guest data is transformed.
    private static final int KD_BRIDGE_PORT = 39100;
    private static final long WINDOWS_TARGET_SIZE = 64L * 1024L * 1024L * 1024L;
    private static final String HEADLESS_SETUP_MEDIA_NAME = "win11-headless-installer-10g.img";
    private static final long HEADLESS_SETUP_MEDIA_MIN_SIZE = 7L * 1024L * 1024L * 1024L;
    private static final String HEADLESS_SETUP_MEDIA_REVISION = "r3-efi-gpt";
    private static final String HEADLESS_BOOT_MEDIA_NAME = "win11-gop-ebs-r1.img";
    private static final long HEADLESS_BOOT_MEDIA_SIZE = 9_126_805_504L;
    private static final String HEADLESS_BOOT_MEDIA_SHA256 = "2582CAE49FDB3BCD7229280DC8595E5407460BCBADED8FF97AEC73D8211278A7";
    // Separate disposable Linux profile.  It intentionally shares only the
    // proven kernel-first AVF topology with Windows; it never patches or
    // overwrites the immutable Windows medium.
    private static final String UBUNTU_GNOME_VM_NAME = "winavf-ubuntu-gnome-24045";
    private static final String UBUNTU_GNOME_MEDIA_NAME = "ubuntu-gnome-24.04.5-v10-fdtclient-cpu0.img";
    private static final long UBUNTU_GNOME_MEDIA_SIZE = 9_126_805_504L;
    private static final String UBUNTU_GNOME_MEDIA_SHA256 = "FB201BABDD0E309D5177D683387495D058ACF910BAAEF8733DCB944CA92E569A";
    // This patch targets only the disposable Ubuntu raw clone above. It makes
    // KvmTool select the normal DXE Device-Tree handoff; Windows media never
    // reads, stages, or receives this bundle.
    private static final String UBUNTU_GNOME_FIRMWARE_PATCH_NAME = "ubuntu-gnome-v11-fdt-dxe-firmware.patch";
    private static final long UBUNTU_GNOME_FIRMWARE_PATCH_SIZE = 4_194_436L;
    private static final String UBUNTU_GNOME_FIRMWARE_PATCH_SHA256 = "9C109F3EB95D1B6F27929D970152725E0F2328A25FC3C847D8ED1603D86EDC55";
    private static final String IMAGE_PATCH_STAGING_NAME = "winavf-image-patch.bin";
    private static final String IMAGE_PATCH_ACTIVE_NAME = "active-image-patch.bin";
    private static final byte[] IMAGE_PATCH_MAGIC = "WAVFPAT1".getBytes(java.nio.charset.StandardCharsets.US_ASCII);
    private TextView status;
    private TextView logText;
    private FrameSurfaceView frameSurface;
    private FrameLayout page;
    private LinearLayout toolbar;
    private LinearLayout settingsPanel;
    private ScrollView logPanel;
    private ConsoleFrameDecoder frameDecoder;
    private boolean frameVisible;
    // A product-path UEFI input probe uses the already-proven serial stream,
    // not an unimplemented input driver. This becomes true only after EDK2
    // emits its real Boot Options prompt on that stream.
    private volatile boolean bootOptionsPromptSeen;
    private volatile boolean serialInputWindowSeen;
    private volatile boolean serialEscapeAcknowledged;
    private volatile int observedFrameCount;
    private final StringBuilder serialProbeTail = new StringBuilder();
    private final StringBuilder uiLog = new StringBuilder();
    private volatile Socket activeKdBridgeSocket;
    private volatile Object activeKdBridgeVm;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);

        // The app is now a guest-display surface, not a test-control panel.
        // Start/rollback/audit remain available through their existing explicit
        // intent extras, so this removes no launch or rollback capability.
        getWindow().setDecorFitsSystemWindows(false);
        WindowInsetsController insets = getWindow().getDecorView().getWindowInsetsController();
        if (insets != null) {
            insets.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
            insets.setSystemBarsBehavior(
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
        }
        page = new FrameLayout(this);
        page.setBackgroundColor(Color.BLACK);

        frameSurface = new FrameSurfaceView(this);
        page.addView(frameSurface, new FrameLayout.LayoutParams(-1, -1));

        status = new TextView(this);
        status.setText("Ready");
        status.setTextColor(Color.LTGRAY);
        status.setTextSize(12);
        status.setSingleLine(true);
        status.setEllipsize(TextUtils.TruncateAt.END);
        status.setPadding(16, 8, 16, 8);
        status.setBackgroundColor(0x99000000);
        FrameLayout.LayoutParams statusLayout = new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM);
        page.addView(status, statusLayout);

        addProductControls();

        frameDecoder = new ConsoleFrameDecoder(new ConsoleFrameDecoder.Listener() {
            @Override public void onFrame(ConsoleFrameDecoder.Frame frame) {
                observedFrameCount++;
                runOnUiThread(() -> {
                    frameSurface.present(frame);
                    // The guest retains the complete canvas. Controls collapse
                    // to a small menu affordance after its first real frame.
                    frameVisible = true;
                    status.setVisibility(View.GONE);
                    toolbar.setVisibility(View.GONE);
                    settingsPanel.setVisibility(View.GONE);
                    logPanel.setVisibility(View.GONE);
                });
            }
            @Override public void onProtocolError(String message) {
                // Serial text and frame records share one pipe; malformed records are recoverable.
            }
        });
        setContentView(page);
        handleIntentActions(getIntent());
    }

    /** Compact product controls; all diagnostic actions remain intent-only. */
    private void addProductControls() {
        Button menu = button("☰");
        menu.setContentDescription("Open WinAVF controls");
        menu.setOnClickListener(v -> {
            boolean open = toolbar.getVisibility() != View.VISIBLE;
            toolbar.setVisibility(open ? View.VISIBLE : View.GONE);
            if (!open) {
                settingsPanel.setVisibility(View.GONE);
                logPanel.setVisibility(View.GONE);
            }
        });
        FrameLayout.LayoutParams menuLayout = new FrameLayout.LayoutParams(dp(48), dp(48), Gravity.TOP | Gravity.START);
        menuLayout.setMargins(dp(10), dp(10), 0, 0);
        page.addView(menu, menuLayout);

        toolbar = new LinearLayout(this);
        toolbar.setOrientation(LinearLayout.HORIZONTAL);
        toolbar.setGravity(Gravity.CENTER_VERTICAL);
        toolbar.setPadding(dp(58), dp(6), dp(8), dp(6));
        toolbar.setBackgroundColor(0xE6161A20);

        TextView title = new TextView(this);
        title.setText("WinAVF");
        title.setTextColor(Color.WHITE);
        title.setTextSize(18);
        title.setGravity(Gravity.CENTER_VERTICAL);
        toolbar.addView(title, new LinearLayout.LayoutParams(0, dp(44), 1f));

        Button launch = button("Launch");
        launch.setOnClickListener(v -> new Thread(this::startTest, "WinAVF-ui-start").start());
        toolbar.addView(launch, new LinearLayout.LayoutParams(-2, dp(44)));
        Button settings = button("Settings");
        settings.setOnClickListener(v -> toggleSettings());
        toolbar.addView(settings, new LinearLayout.LayoutParams(-2, dp(44)));
        Button logs = button("Logs");
        logs.setOnClickListener(v -> toggleLogs());
        toolbar.addView(logs, new LinearLayout.LayoutParams(-2, dp(44)));
        FrameLayout.LayoutParams toolbarLayout = new FrameLayout.LayoutParams(-1, dp(60), Gravity.TOP);
        page.addView(toolbar, toolbarLayout);

        settingsPanel = new LinearLayout(this);
        settingsPanel.setOrientation(LinearLayout.VERTICAL);
        settingsPanel.setPadding(dp(18), dp(14), dp(18), dp(14));
        settingsPanel.setBackgroundColor(0xF0181D24);
        TextView settingsText = new TextView(this);
        settingsText.setTextColor(Color.LTGRAY);
        settingsText.setTextSize(14);
        settingsText.setText("Launch profile\n\n"
                + "• 1 vCPU · verified AVF topology\n"
                + "• EDK2 GOP → protected WAVF display\n"
                + "• Windows media is verified before launch\n"
                + "• Image changes use a transactional path only\n\n"
                + "Hardware settings are locked. CPU, ACPI, BCD and timer experiments are intentionally disabled.");
        settingsPanel.addView(settingsText, new LinearLayout.LayoutParams(-1, -2));
        settingsPanel.setVisibility(View.GONE);
        FrameLayout.LayoutParams settingsLayout = new FrameLayout.LayoutParams(dp(330), -2, Gravity.TOP | Gravity.END);
        settingsLayout.setMargins(0, dp(70), dp(10), 0);
        page.addView(settingsPanel, settingsLayout);

        logPanel = new ScrollView(this);
        logPanel.setFillViewport(true);
        logPanel.setBackgroundColor(0xF0101419);
        logText = new TextView(this);
        logText.setTextColor(0xFFD4D8DD);
        logText.setTextSize(12);
        logText.setTypeface(android.graphics.Typeface.MONOSPACE);
        logText.setPadding(dp(14), dp(12), dp(14), dp(12));
        logPanel.addView(logText, new ScrollView.LayoutParams(-1, -2));
        logPanel.setVisibility(View.GONE);
        FrameLayout.LayoutParams logsLayout = new FrameLayout.LayoutParams(-1, dp(300), Gravity.BOTTOM);
        logsLayout.setMargins(dp(10), 0, dp(10), dp(10));
        page.addView(logPanel, logsLayout);
    }

    private Button button(String text) {
        Button result = new Button(this);
        result.setText(text);
        result.setTextSize(13);
        result.setTextColor(Color.WHITE);
        result.setAllCaps(false);
        result.setBackgroundColor(0xFF242B35);
        return result;
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private void toggleSettings() {
        boolean show = settingsPanel.getVisibility() != View.VISIBLE;
        settingsPanel.setVisibility(show ? View.VISIBLE : View.GONE);
        if (show) logPanel.setVisibility(View.GONE);
    }

    private void toggleLogs() {
        boolean show = logPanel.getVisibility() != View.VISIBLE;
        if (show) refreshLogPanel();
        logPanel.setVisibility(show ? View.VISIBLE : View.GONE);
        if (show) settingsPanel.setVisibility(View.GONE);
    }

    private void refreshLogPanel() {
        String serial = readTail(new File(getExternalFilesDir(null), "serial.log"), 16 * 1024);
        logText.setText("WINAVF EVENT LOG\n" + uiLog + (serial.isEmpty() ? "" : "\nRAW SERIAL TAIL\n" + serial));
    }

    private static String readTail(File file, int maxBytes) {
        if (!file.isFile()) return "";
        try (RandomAccessFile input = new RandomAccessFile(file, "r")) {
            long offset = Math.max(0, input.length() - maxBytes);
            input.seek(offset);
            byte[] bytes = new byte[(int) (input.length() - offset)];
            input.readFully(bytes);
            return new String(bytes, java.nio.charset.StandardCharsets.UTF_8);
        } catch (Throwable ignored) { return ""; }
    }

    @Override public void onNewIntent(android.content.Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIntentActions(intent);
    }

    /** Allows a deterministic external stop/rollback intent to reach an existing Activity. */
    private void handleIntentActions(android.content.Intent intent) {
        if (intent.getBooleanExtra("start", false)) {
            new Thread(this::startTest, "WinAVF-start").start();
        }
        if (intent.getBooleanExtra("ubuntu_gnome", false)) {
            new Thread(this::startUbuntuGnome, "WinAVF-ubuntu-gnome").start();
        }
        if (intent.getBooleanExtra("ubuntu_gnome_cleanup", false)) {
            new Thread(this::cleanupUbuntuGnome, "WinAVF-ubuntu-gnome-cleanup").start();
        }
        if (intent.getBooleanExtra("uefi_input_probe", false)) {
            new Thread(this::startUefiInputProbe, "WinAVF-uefi-input").start();
        }
        if (intent.getBooleanExtra("uefi_serial_escape_probe", false)) {
            new Thread(this::startUefiSerialEscapeProbe, "WinAVF-uefi-serial-escape").start();
        }
        if (intent.getBooleanExtra("vsock_hello_probe", false)) {
            new Thread(this::startVsockHelloProbe, "WinAVF-vsock-hello").start();
        }
        if (intent.getBooleanExtra("rollback", false)) {
            new Thread(this::rollbackLastPatch, "WinAVF-rollback").start();
        }
        if (intent.getBooleanExtra("audit", false)) {
            new Thread(this::auditVirtualizationCapabilities, "WinAVF-audit").start();
        }
        if (intent.getBooleanExtra("synthetic_frame", false)) {
            emitSyntheticFrameForSurfaceAudit();
        }
        if (intent.getBooleanExtra("display_host_audit", false)) {
            new Thread(this::auditNativeAvfDisplayAccess, "WinAVF-display-audit").start();
        }
        if (intent.getBooleanExtra("console_input_api_probe", false)) {
            new Thread(this::probeConsoleInputApi, "WinAVF-console-input-api").start();
        }
        if (intent.getBooleanExtra("console_binary_loopback", false)) {
            new Thread(this::probeConsoleBinaryLoopback, "WinAVF-console-binary-loopback").start();
        }
        if (intent.getBooleanExtra("cleanup_console_binary_loopback", false)) {
            new Thread(this::cleanupConsoleBinaryLoopback, "WinAVF-console-binary-cleanup").start();
        }
        if (intent.getBooleanExtra("kd_bridge", false)) {
            final String token = intent.getStringExtra("kd_token");
            new Thread(() -> startProductKdBridge(token), "WinAVF-product-kd-bridge").start();
        }
        if (intent.getBooleanExtra("kd_bridge_stop", false)) {
            new Thread(this::stopProductKdBridge, "WinAVF-product-kd-stop").start();
        }
        if (intent.getBooleanExtra("export_product_bcd", false)) {
            new Thread(this::exportProductBcdReadOnly, "WinAVF-product-bcd-audit").start();
        }
        if (intent.getBooleanExtra("persistent_witness_audit", false)) {
            new Thread(this::auditPersistentBootWitness, "WinAVF-persistent-witness-audit").start();
        }
        if (intent.getBooleanExtra("persistent_witness_cleanup", false)) {
            new Thread(this::cleanupPersistentBootWitness, "WinAVF-persistent-witness-cleanup").start();
        }
    }

    /** UI-only decoder/surface audit; it does not create a VM or touch media. */
    private void emitSyntheticFrameForSurfaceAudit() {
        final int width = 320, height = 200, payloadBytes = width * height * 4;
        byte[] record = new byte[28 + payloadBytes];
        record[0] = 'W'; record[1] = 'A'; record[2] = 'V'; record[3] = 'F';
        record[4] = 1; record[5] = 1;
        putLe16(record, 8, width); putLe16(record, 10, height);
        putLe32(record, 12, 0x53594631); putLe32(record, 16, payloadBytes);
        for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
            int p = 28 + (y * width + x) * 4;
            record[p] = (byte) (x * 255 / (width - 1));
            record[p + 1] = (byte) (y * 255 / (height - 1));
            record[p + 2] = (byte) 0x80; record[p + 3] = (byte) 0xff;
        }
        CRC32 crc = new CRC32(); crc.update(record, 28, payloadBytes);
        putLe32(record, 20, (int) crc.getValue());
        frameDecoder.feed(record, 0, record.length);
        show("Synthetic WAVF surface audit frame submitted.");
    }
    private static void putLe16(byte[] target, int offset, int value) {
        target[offset] = (byte) value; target[offset + 1] = (byte) (value >>> 8);
    }
    private static void putLe32(byte[] target, int offset, int value) {
        target[offset] = (byte) value; target[offset + 1] = (byte) (value >>> 8);
        target[offset + 2] = (byte) (value >>> 16); target[offset + 3] = (byte) (value >>> 24);
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

    /**
     * Read-only reachability check for the Android 16 Terminal display path.
     * It never creates a VM, calls waitDisplayService(), or submits a Surface.
     * The report distinguishes a hidden-API/class-loader restriction from a
     * missing virtualization-service Binder without perturbing a running VM.
     */
    private void auditNativeAvfDisplayAccess() {
        File report = new File(getExternalFilesDir(null), "native-avf-display-access-audit.txt");
        try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
            out.println("fingerprint=" + android.os.Build.FINGERPRINT);
            out.println("uid=" + android.os.Process.myUid());
            out.println("permission.MANAGE_VIRTUAL_MACHINE="
                    + checkSelfPermission("android.permission.MANAGE_VIRTUAL_MACHINE"));
            out.println("permission.USE_CUSTOM_VIRTUAL_MACHINE="
                    + checkSelfPermission("android.permission.USE_CUSTOM_VIRTUAL_MACHINE"));

            Class<?> serviceManager = Class.forName("android.os.ServiceManager");
            out.println("CLASS android.os.ServiceManager=AVAILABLE");
            Method getService = serviceManager.getMethod("getService", String.class);
            out.println("METHOD ServiceManager.getService=AVAILABLE");
            Object service = getService.invoke(null, "android.system.virtualizationservice");
            out.println("BINDER android.system.virtualizationservice="
                    + (service == null ? "NULL" : "AVAILABLE:" + service.getClass().getName()));

            for (String name : new String[] {
                    "android.system.virtualizationservice_internal.IVirtualizationServiceInternal",
                    "android.system.virtualizationservice_internal.IVirtualizationServiceInternal$Stub",
                    "android.crosvm.ICrosvmAndroidDisplayService",
                    "android.crosvm.ICrosvmAndroidDisplayService$Stub"
            }) {
                try {
                    Class.forName(name);
                    out.println("CLASS " + name + "=AVAILABLE");
                } catch (Throwable error) {
                    out.println("CLASS " + name + "=UNAVAILABLE:" + rootMessage(error));
                }
            }
            out.println("RESULT=READ_ONLY_HOST_PATH_AUDIT_COMPLETE");
        } catch (Throwable error) {
            show("Native AVF display access audit failed: " + rootMessage(error));
            return;
        }
        show("Native AVF display access audit saved to " + report.getAbsolutePath());
    }

    /**
     * Proves only that the app can obtain the AVF console-input stream.  It
     * creates an app-owned custom VM with the existing kernel wrapper but no
     * disk, does not call run(), writes no guest bytes, and deletes the VM in
     * the finally block.  It cannot touch the product Windows medium.
     */
    private void probeConsoleInputApi() {
        File report = new File(getExternalFilesDir(null), "console-input-api-probe.txt");
        Object manager = null;
        boolean created = false;
        try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
            out.println("scope=NO_GUEST_RUN_NO_DISK_NO_PRODUCT_MEDIA");
            Class<?> vmConfig = Class.forName("android.system.virtualmachine.VirtualMachineConfig");
            Class<?> builder = Class.forName(vmConfig.getName() + "$Builder");
            Object config = builder.getConstructor(android.content.Context.class).newInstance(this);
            call(config, "setProtectedVm", boolean.class, false);
            call(config, "setDebugLevel", int.class, 1);
            call(config, "setConsoleInputDevice", String.class, "ttyS0");
            call(config, "setVmConsoleInputSupported", boolean.class, true);
            File payload = new File(getFilesDir(), "payload");
            if (!payload.exists() && !payload.mkdirs()) throw new IllegalStateException("Cannot create payload directory");
            File kernel = copyAsset("u-boot-wrapper-v24.Image", new File(payload, "u-boot-wrapper-v24.Image"), -1L);
            Class<?> custom = Class.forName("android.system.virtualmachine.VirtualMachineCustomImageConfig");
            Class<?> customBuilder = Class.forName(custom.getName() + "$Builder");
            Object image = customBuilder.getConstructor().newInstance();
            call(image, "setName", String.class, CONSOLE_INPUT_PROBE_VM_NAME);
            call(image, "setOsName", String.class, "winavf-console-input-probe");
            call(image, "setKernelPath", String.class, kernel.getAbsolutePath());
            Object customConfig = call(image, "build");
            call(config, "setCustomImageConfig", custom, customConfig);
            Object finalConfig = call(config, "build");
            boolean enabled = (Boolean) finalConfig.getClass().getMethod("isVmConsoleInputSupported").invoke(finalConfig);
            out.println("config.isVmConsoleInputSupported=" + enabled);
            if (!enabled) throw new IllegalStateException("Console-input flag was not persisted in config");

            Class<?> managerClass = Class.forName("android.system.virtualmachine.VirtualMachineManager");
            manager = getSystemService((Class) managerClass);
            Object prior = manager.getClass().getMethod("get", String.class).invoke(manager, CONSOLE_INPUT_PROBE_VM_NAME);
            if (prior != null) manager.getClass().getMethod("delete", String.class).invoke(manager, CONSOLE_INPUT_PROBE_VM_NAME);
            Object vm = manager.getClass().getMethod("create", String.class, finalConfig.getClass())
                    .invoke(manager, CONSOLE_INPUT_PROBE_VM_NAME, finalConfig);
            created = true;
            OutputStream input = (OutputStream) vm.getClass().getMethod("getConsoleInput").invoke(vm);
            // This is intentionally a zero-byte operation: it tests the Java
            // stream object only and cannot inject a command into any guest.
            input.write(new byte[0]);
            input.flush();
            input.close();
            out.println("getConsoleInput=OUTPUT_STREAM_USABLE");
            out.println("result=PASS");
            show("Console input API probe: OutputStream acquired.");
        } catch (Throwable error) {
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, true))) {
                out.println("result=FAIL");
                out.println("error=" + rootMessage(error));
            } catch (Throwable ignored) { }
            show("Console input API probe failed: " + rootMessage(error));
        } finally {
            if (created && manager != null) {
                try { manager.getClass().getMethod("delete", String.class).invoke(manager, CONSOLE_INPUT_PROBE_VM_NAME); }
                catch (Throwable ignored) { }
            }
        }
    }

    /**
     * One isolated end-to-end binary test for app-owned console RX.  The guest
     * is a 16550 echo loop with no disk and no Windows assets.  A marker gates
     * transmission; the returned bytes are compared byte-for-byte and saved.
     */
    private void probeConsoleBinaryLoopback() {
        File report = new File(getExternalFilesDir(null), "console-binary-loopback-report.txt");
        File rawLog = new File(getExternalFilesDir(null), "console-binary-loopback.raw");
        Object manager = null;
        Object vm = null;
        InputStream console = null;
        OutputStream input = null;
        final Object lock = new Object();
        final ByteArrayOutputStream captured = new ByteArrayOutputStream();
        try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
            out.println("scope=DISPOSABLE_NO_DISK_NO_WINDOWS_NO_PRODUCT_MEDIA");
            byte[] expected = new byte[CONSOLE_BINARY_ECHO_BYTES];
            for (int i = 0; i < expected.length; ++i) expected[i] = (byte) i;
            out.println("patternBytes=" + expected.length);
            out.println("patternSha256=" + hex(sha256(expected)));

            File payload = new File(getFilesDir(), "payload");
            if (!payload.exists() && !payload.mkdirs()) throw new IllegalStateException("Cannot create payload directory");
            File kernel = copyAsset("console-binary-echo.Image", new File(payload, "console-binary-echo.Image"), -1L);
            Object config = buildConsoleBinaryEchoConfig(kernel);
            if (!(Boolean) config.getClass().getMethod("isVmConsoleInputSupported").invoke(config)) {
                throw new IllegalStateException("Console input was not persisted in loopback config");
            }
            Class<?> managerClass = Class.forName("android.system.virtualmachine.VirtualMachineManager");
            manager = getSystemService((Class) managerClass);
            Object prior = manager.getClass().getMethod("get", String.class).invoke(manager, CONSOLE_BINARY_ECHO_VM_NAME);
            if (prior != null) manager.getClass().getMethod("delete", String.class).invoke(manager, CONSOLE_BINARY_ECHO_VM_NAME);
            vm = manager.getClass().getMethod("create", String.class, config.getClass()).invoke(manager, CONSOLE_BINARY_ECHO_VM_NAME, config);
            console = (InputStream) vm.getClass().getMethod("getConsoleOutput").invoke(vm);
            input = (OutputStream) vm.getClass().getMethod("getConsoleInput").invoke(vm);
            final InputStream readerConsole = console;
            Thread reader = new Thread(() -> {
                byte[] buf = new byte[512];
                try {
                    for (int n; (n = readerConsole.read(buf)) >= 0;) {
                        synchronized (lock) { captured.write(buf, 0, n); lock.notifyAll(); }
                    }
                } catch (Throwable ignored) { }
            }, "WinAVF-console-binary-reader");
            reader.setDaemon(true);
            reader.start();
            vm.getClass().getMethod("run").invoke(vm);

            int markerOffset = waitForBytes(captured, lock, CONSOLE_BINARY_ECHO_READY, 8000);
            if (markerOffset < 0) throw new IllegalStateException("Guest readiness marker not observed");
            out.println("readyMarkerOffset=" + markerOffset);
            input.write(expected);
            input.flush();
            out.println("patternTransmitted=true");
            if (!waitForLength(captured, lock, markerOffset + CONSOLE_BINARY_ECHO_READY.length + expected.length, 8000)) {
                throw new IllegalStateException("Timed out waiting for echoed pattern");
            }
            byte[] all;
            synchronized (lock) { all = captured.toByteArray(); }
            byte[] echoed = Arrays.copyOfRange(all, markerOffset + CONSOLE_BINARY_ECHO_READY.length,
                    markerOffset + CONSOLE_BINARY_ECHO_READY.length + expected.length);
            try (FileOutputStream raw = new FileOutputStream(rawLog, false)) { raw.write(all); }
            out.println("echoedBytes=" + echoed.length);
            out.println("echoedSha256=" + hex(sha256(echoed)));
            out.println("byteExact=" + Arrays.equals(expected, echoed));
            if (!Arrays.equals(expected, echoed)) throw new IllegalStateException("Echoed bytes differ from transmitted pattern");
            out.println("result=PASS");
            show("Console binary loopback PASS: 4096/4096 exact.");
        } catch (Throwable error) {
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, true))) {
                out.println("result=FAIL");
                out.println("error=" + rootMessage(error));
            } catch (Throwable ignored) { }
            show("Console binary loopback failed: " + rootMessage(error));
        } finally {
            try { if (input != null) input.close(); } catch (Throwable ignored) { }
            try { if (console != null) console.close(); } catch (Throwable ignored) { }
            if (vm != null) {
                try { vm.getClass().getMethod("stop").invoke(vm); } catch (Throwable ignored) { }
            }
            if (manager != null) {
                try { manager.getClass().getMethod("delete", String.class).invoke(manager, CONSOLE_BINARY_ECHO_VM_NAME); }
                catch (Throwable ignored) { }
            }
        }
    }

    /** Cleans only the named no-disk loopback VM left by an interrupted probe. */
    private void cleanupConsoleBinaryLoopback() {
        try {
            Class<?> managerClass = Class.forName("android.system.virtualmachine.VirtualMachineManager");
            Object manager = getSystemService((Class) managerClass);
            Object vm = manager.getClass().getMethod("get", String.class).invoke(manager, CONSOLE_BINARY_ECHO_VM_NAME);
            if (vm != null) {
                try { vm.getClass().getMethod("stop").invoke(vm); } catch (Throwable ignored) { }
            }
            manager.getClass().getMethod("delete", String.class).invoke(manager, CONSOLE_BINARY_ECHO_VM_NAME);
            show("Console binary loopback VM removed.");
        } catch (Throwable error) {
            show("Console binary loopback cleanup failed: " + rootMessage(error));
        }
    }

    private Object buildConsoleBinaryEchoConfig(File kernel) throws Exception {
        Class<?> custom = Class.forName("android.system.virtualmachine.VirtualMachineCustomImageConfig");
        Class<?> customBuilder = Class.forName(custom.getName() + "$Builder");
        Object image = customBuilder.getConstructor().newInstance();
        call(image, "setName", String.class, CONSOLE_BINARY_ECHO_VM_NAME);
        call(image, "setOsName", String.class, "winavf-console-binary-echo");
        call(image, "setKernelPath", String.class, kernel.getAbsolutePath());
        Object customConfig = call(image, "build");
        Class<?> vmConfig = Class.forName("android.system.virtualmachine.VirtualMachineConfig");
        Class<?> builder = Class.forName(vmConfig.getName() + "$Builder");
        Object config = builder.getConstructor(android.content.Context.class).newInstance(this);
        call(config, "setProtectedVm", boolean.class, false);
        call(config, "setDebugLevel", int.class, 1);
        call(config, "setCpuTopology", int.class, vmConfig.getField("CPU_TOPOLOGY_ONE_CPU").getInt(null));
        call(config, "setMemoryBytes", long.class, 512L * 1024L * 1024L);
        call(config, "setConsoleInputDevice", String.class, "ttyS0");
        call(config, "setVmOutputCaptured", boolean.class, true);
        call(config, "setVmConsoleInputSupported", boolean.class, true);
        call(config, "setCustomImageConfig", custom, customConfig);
        return call(config, "build");
    }

    private static boolean waitForLength(ByteArrayOutputStream captured, Object lock, int required, long timeoutMs) throws InterruptedException {
        long deadline = System.currentTimeMillis() + timeoutMs;
        synchronized (lock) {
            while (captured.size() < required) {
                long remaining = deadline - System.currentTimeMillis();
                if (remaining <= 0) return false;
                lock.wait(remaining);
            }
            return true;
        }
    }

    private static int waitForBytes(ByteArrayOutputStream captured, Object lock, byte[] needle, long timeoutMs) throws InterruptedException {
        long deadline = System.currentTimeMillis() + timeoutMs;
        synchronized (lock) {
            for (;;) {
                byte[] bytes = captured.toByteArray();
                for (int i = 0; i <= bytes.length - needle.length; ++i) {
                    boolean match = true;
                    for (int j = 0; j < needle.length; ++j) if (bytes[i + j] != needle[j]) { match = false; break; }
                    if (match) return i;
                }
                long remaining = deadline - System.currentTimeMillis();
                if (remaining <= 0) return -1;
                lock.wait(remaining);
            }
        }
    }

    private static String hex(byte[] bytes) { return java.util.HexFormat.of().formatHex(bytes).toUpperCase(java.util.Locale.ROOT); }

    private void startTest() {
        startTest(false, false, false);
    }

    /** One opt-in host-to-virtio-keyboard probe; it never alters guest media. */
    private void startUefiInputProbe() {
        startTest(true, false, false);
    }

    /**
     * One product-topology probe for the standard EDK2 serial ConIn path.
     * The console's TX side can batch an idle-window marker until that window
     * ends. After the earlier Boot Options prompt, send a bounded low-rate ESC
     * stream until firmware acknowledges actual ConIn consumption.
     */
    private void startUefiSerialEscapeProbe() {
        startTest(false, false, true);
    }

    /** One opt-in post-EBS raw-vsock HELLO probe; it never sends input events. */
    private void startVsockHelloProbe() {
        startTest(false, true, false);
    }

    private void startTest(boolean enableKeyboardProbe, boolean enableVsockHelloProbe, boolean enableSerialEscapeProbe) {
        try {
            bootOptionsPromptSeen = false;
            serialInputWindowSeen = false;
            serialEscapeAcknowledged = false;
            observedFrameCount = 0;
            serialProbeTail.setLength(0);
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
            File esp = copyFile(bootMedia, new File(payload, HEADLESS_BOOT_MEDIA_NAME), HEADLESS_BOOT_MEDIA_SIZE, false);
            applyStagedImagePatch(payload, esp);
            show("Using the preserved Windows Boot Manager milestone medium only…");
            show("Creating custom AVF VM through Android API…");
            Object config = buildConfig(kernel, esp, enableKeyboardProbe);
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
            if (enableKeyboardProbe) startEscInputProbe(vm);
            if (enableSerialEscapeProbe) startSerialEscapeInputProbe(vm);
            if (enableVsockHelloProbe) startVsockHelloProbe(vm);
            startWinpeMarkerReporter(esp);
            show("VM launched. Waiting for kernel-first serial output…");
        } catch (Throwable t) {
            show("FAILED: " + rootMessage(t));
        }
    }

    /**
     * Starts a wholly separate Ubuntu Desktop live-media profile.  The Linux
     * image is disposable and has its own app-private disk/VM name, so this
     * cannot modify the Windows milestone medium or its rollback state.
     */
    private void startUbuntuGnome() {
        try {
            frameVisible = false;
            observedFrameCount = 0;
            File payload = new File(getFilesDir(), "ubuntu-gnome-payload");
            if (!payload.exists() && !payload.mkdirs()) throw new IllegalStateException("Cannot create Ubuntu payload directory");
            File kernel = copyAsset("u-boot-wrapper-v24.Image", new File(payload, "u-boot-wrapper-v24.Image"), -1L);
            File staged = new File(getExternalFilesDir(null), UBUNTU_GNOME_MEDIA_NAME);
            if (!staged.isFile() || staged.length() != UBUNTU_GNOME_MEDIA_SIZE) {
                throw new IllegalStateException("Missing Ubuntu GNOME staging medium: " + staged);
            }
            if (!UBUNTU_GNOME_MEDIA_SHA256.equals(hex(sha256File(staged)))) {
                throw new SecurityException("Ubuntu GNOME staging hash mismatch");
            }
            File disk = copyFile(staged, new File(payload, UBUNTU_GNOME_MEDIA_NAME), UBUNTU_GNOME_MEDIA_SIZE, false);
            // The Android-private copy is the actual crosvm backing file.  A
            // matching staging hash and file length alone do not prove that a
            // long copy reached this file byte-for-byte.  Gate the disposable
            // Linux launch on its own full hash before applying the local FD
            // patch, so a live-root read failure cannot be misclassified as a
            // Linux, FDT, or virtio regression.
            if (!UBUNTU_GNOME_MEDIA_SHA256.equals(hex(sha256File(disk)))) {
                throw new SecurityException("Ubuntu GNOME private-media hash mismatch");
            }
            File stagedFirmwarePatch = new File(getExternalFilesDir(null), UBUNTU_GNOME_FIRMWARE_PATCH_NAME);
            if (!stagedFirmwarePatch.isFile() || stagedFirmwarePatch.length() != UBUNTU_GNOME_FIRMWARE_PATCH_SIZE) {
                throw new IllegalStateException("Missing Ubuntu-only FDT firmware patch: " + stagedFirmwarePatch);
            }
            if (!UBUNTU_GNOME_FIRMWARE_PATCH_SHA256.equals(hex(sha256File(stagedFirmwarePatch)))) {
                throw new SecurityException("Ubuntu-only FDT firmware patch hash mismatch");
            }
            File privateFirmwarePatch = copyFile(
                    stagedFirmwarePatch,
                    new File(payload, UBUNTU_GNOME_FIRMWARE_PATCH_NAME),
                    UBUNTU_GNOME_FIRMWARE_PATCH_SIZE,
                    false);
            applyPatch(privateFirmwarePatch, disk, false);
            Object config = buildConfig(kernel, disk, false, UBUNTU_GNOME_VM_NAME);
            Object manager = getSystemService((Class) Class.forName("android.system.virtualmachine.VirtualMachineManager"));
            try {
                Object prior = manager.getClass().getMethod("get", String.class).invoke(manager, UBUNTU_GNOME_VM_NAME);
                if (prior != null) manager.getClass().getMethod("delete", String.class).invoke(manager, UBUNTU_GNOME_VM_NAME);
            } catch (Exception ignored) { }
            Object vm = manager.getClass().getMethod("create", String.class, config.getClass()).invoke(manager, UBUNTU_GNOME_VM_NAME, config);
            attachCallback(vm);
            InputStream console = (InputStream) vm.getClass().getMethod("getConsoleOutput").invoke(vm);
            startConsoleReader(console, "ubuntu-gnome-serial.log");
            vm.getClass().getMethod("run").invoke(vm);
            startUbuntuVsockHelloProbe(vm);
            show("Ubuntu GNOME live profile launched; capturing its complete serial log.");
        } catch (Throwable t) {
            show("Ubuntu GNOME launch failed: " + rootMessage(t));
        }
    }

    /** Deletes only the stopped, disposable Ubuntu GNOME VM and its private disk. */
    private void cleanupUbuntuGnome() {
        File report = new File(getExternalFilesDir(null), "ubuntu-gnome-cleanup-report.txt");
        try {
            Object manager = getSystemService((Class) Class.forName("android.system.virtualmachine.VirtualMachineManager"));
            try {
                Object prior = manager.getClass().getMethod("get", String.class).invoke(manager, UBUNTU_GNOME_VM_NAME);
                if (prior != null) {
                    try { prior.getClass().getMethod("stop").invoke(prior); } catch (Throwable ignored) { }
                    manager.getClass().getMethod("delete", String.class).invoke(manager, UBUNTU_GNOME_VM_NAME);
                }
            } catch (Exception ignored) { }
            File payload = new File(getFilesDir(), "ubuntu-gnome-payload");
            File disk = new File(payload, UBUNTU_GNOME_MEDIA_NAME);
            if (disk.exists() && !disk.delete()) throw new IllegalStateException("Could not delete disposable Ubuntu disk");
            File loader = new File(payload, "u-boot-wrapper-v24.Image");
            if (loader.exists() && !loader.delete()) throw new IllegalStateException("Could not delete disposable Ubuntu loader copy");
            File firmwarePatch = new File(payload, UBUNTU_GNOME_FIRMWARE_PATCH_NAME);
            if (firmwarePatch.exists() && !firmwarePatch.delete()) throw new IllegalStateException("Could not delete disposable Ubuntu firmware patch");
            if (payload.exists() && !payload.delete()) throw new IllegalStateException("Could not delete empty Ubuntu payload directory");
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                out.println("RESULT=PASS");
                out.println("SCOPE=ubuntu-gnome-payload-only");
                out.println("WINDOWS_PAYLOAD_UNTOUCHED=true");
            }
            show("Disposed the separate Ubuntu GNOME profile; Windows media was untouched.");
        } catch (Throwable t) {
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                out.println("RESULT=FAIL"); out.println("ERROR=" + rootMessage(t));
            } catch (Throwable ignored) { }
            show("Ubuntu GNOME cleanup failed: " + rootMessage(t));
        }
    }

    /**
     * Runs the unchanged product VM topology while relaying the already-proven
     * ttyS0 streams byte-for-byte to a localhost TCP peer.  The bridge itself
     * does not create or alter a patch; the normal transactional launcher path
     * is retained, including its baseline verification and rollback record.
     */
    private void startProductKdBridge(String token) {
        File report = new File(getExternalFilesDir(null), "product-kd-bridge-report.txt");
        if (token == null || !token.matches("[0-9A-Fa-f]{32,128}")) {
            writeBridgeFailure(report, "invalid diagnostic capability token");
            return;
        }
        try (ServerSocket listener = new ServerSocket(KD_BRIDGE_PORT, 1, InetAddress.getLoopbackAddress())) {
            listener.setSoTimeout(45_000);
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                out.println("scope=APP_OWNED_PRODUCT_VM_RAW_KD_BRIDGE");
                out.println("listener=127.0.0.1:" + KD_BRIDGE_PORT);
                out.println("state=LISTENING");
                out.flush();
                show("KD bridge waiting for the host connection…");
                Socket socket = listener.accept();
                socket.setTcpNoDelay(true);
                // The host creates its debugger endpoint after connecting
                // through adb forwarding; allow that bounded setup time.
                // No VM or patch exists until this token is accepted.
                socket.setSoTimeout(45_000);
                byte[] supplied = readExactly(socket.getInputStream(), token.length());
                if (!token.equals(new String(supplied, java.nio.charset.StandardCharsets.US_ASCII))) {
                    throw new SecurityException("KD bridge capability token mismatch");
                }
                socket.getOutputStream().write("WINAVF_KD_BRIDGE_OK\n".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
                socket.getOutputStream().flush();
                socket.setSoTimeout(0);
                activeKdBridgeSocket = socket;
                out.println("state=HOST_AUTHENTICATED");
                out.flush();

                File payload = new File(getFilesDir(), "payload");
                if (!payload.exists() && !payload.mkdirs()) throw new IllegalStateException("Cannot create payload directory");
                File kernel = copyAsset("u-boot-wrapper-v24.Image", new File(payload, "u-boot-wrapper-v24.Image"), -1L);
                File bootMedia = new File(getExternalFilesDir(null), HEADLESS_BOOT_MEDIA_NAME);
                if (!bootMedia.isFile() || bootMedia.length() != HEADLESS_BOOT_MEDIA_SIZE) {
                    throw new IllegalStateException("Missing compact headless boot medium: " + bootMedia);
                }
                File esp = copyFile(bootMedia, new File(payload, HEADLESS_BOOT_MEDIA_NAME), HEADLESS_BOOT_MEDIA_SIZE, false);
                applyStagedImagePatch(payload, esp);
                Object config = buildConfig(kernel, esp, false);
                Object manager = getSystemService((Class) Class.forName("android.system.virtualmachine.VirtualMachineManager"));
                try {
                    Object prior = manager.getClass().getMethod("get", String.class).invoke(manager, VM_NAME);
                    if (prior != null) manager.getClass().getMethod("delete", String.class).invoke(manager, VM_NAME);
                } catch (Exception ignored) { }
                Object vm = manager.getClass().getMethod("create", String.class, config.getClass()).invoke(manager, VM_NAME, config);
                activeKdBridgeVm = vm;
                attachCallback(vm);
                InputStream consoleOut = (InputStream) vm.getClass().getMethod("getConsoleOutput").invoke(vm);
                OutputStream consoleIn = (OutputStream) vm.getClass().getMethod("getConsoleInput").invoke(vm);
                out.println("state=VM_CREATED");
                out.flush();
                startProductKdBridgePumps(consoleOut, consoleIn, socket);
                vm.getClass().getMethod("run").invoke(vm);
                out.println("state=VM_RUNNING");
                out.flush();
                show("Product KD bridge running on raw ttyS0.");
                while (!socket.isClosed()) Thread.sleep(1000);
            }
        } catch (Throwable error) {
            writeBridgeFailure(report, rootMessage(error));
            show("Product KD bridge failed: " + rootMessage(error));
        } finally {
            activeKdBridgeSocket = null;
            activeKdBridgeVm = null;
        }
    }

    private static byte[] readExactly(InputStream input, int length) throws Exception {
        byte[] result = new byte[length];
        int offset = 0;
        while (offset < length) {
            int n = input.read(result, offset, length - offset);
            if (n < 0) throw new java.io.EOFException("short bridge capability token");
            offset += n;
        }
        return result;
    }

    private void startProductKdBridgePumps(InputStream consoleOut, OutputStream consoleIn, Socket socket) {
        final File received = new File(getExternalFilesDir(null), "product-kd-bridge-rx.bin");
        final File sent = new File(getExternalFilesDir(null), "product-kd-bridge-tx.bin");
        new Thread(() -> {
            try (FileOutputStream raw = new FileOutputStream(received, false);
                 OutputStream peer = socket.getOutputStream()) {
                byte[] buffer = new byte[4096];
                for (int n; (n = consoleOut.read(buffer)) >= 0;) {
                    raw.write(buffer, 0, n); raw.flush();
                    peer.write(buffer, 0, n); peer.flush();
                    frameDecoder.feed(buffer, 0, n);
                }
            } catch (Throwable ignored) { closeQuietly(socket); }
        }, "WinAVF-product-kd-rx").start();
        new Thread(() -> {
            try (FileOutputStream raw = new FileOutputStream(sent, false);
                 InputStream peer = socket.getInputStream()) {
                byte[] buffer = new byte[4096];
                for (int n; (n = peer.read(buffer)) >= 0;) {
                    raw.write(buffer, 0, n); raw.flush();
                    consoleIn.write(buffer, 0, n); consoleIn.flush();
                }
            } catch (Throwable ignored) { closeQuietly(socket); }
        }, "WinAVF-product-kd-tx").start();
    }

    private void stopProductKdBridge() {
        try {
            Object vm = activeKdBridgeVm;
            if (vm == null) {
                Object manager = getSystemService((Class) Class.forName("android.system.virtualmachine.VirtualMachineManager"));
                vm = manager.getClass().getMethod("get", String.class).invoke(manager, VM_NAME);
            }
            if (vm != null) vm.getClass().getMethod("stop").invoke(vm);
        } catch (Throwable ignored) { }
        closeQuietly(activeKdBridgeSocket);
        show("Product KD bridge stop requested.");
    }

    private static void closeQuietly(Socket socket) {
        if (socket == null) return;
        try { socket.close(); } catch (Throwable ignored) { }
    }

    private static void writeBridgeFailure(File report, String error) {
        try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
            out.println("scope=APP_OWNED_PRODUCT_VM_RAW_KD_BRIDGE");
            out.println("state=FAILED");
            out.println("error=" + error);
        } catch (Throwable ignored) { }
    }

    /** Reads and exports only the current ESP BCD; it never opens the image writable. */
    private void exportProductBcdReadOnly() {
        File report = new File(getExternalFilesDir(null), "product-bcd-readonly-report.txt");
        File output = new File(getExternalFilesDir(null), "product-bcd-readonly.bin");
        try {
            File image = new File(getExternalFilesDir(null), HEADLESS_BOOT_MEDIA_NAME);
            byte[] bcd = readFat32File(image, "EFI", "MICROSOFT", "BOOT", "BCD");
            try (FileOutputStream stream = new FileOutputStream(output, false)) { stream.write(bcd); stream.getFD().sync(); }
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                out.println("scope=READ_ONLY_PRODUCT_BASELINE_BCD_EXPORT");
                out.println("imageBytes=" + image.length());
                out.println("bcdBytes=" + bcd.length);
                out.println("bcdSha256=" + hex(sha256(bcd)));
                out.println("result=PASS");
            }
            show("Read-only product BCD export complete.");
        } catch (Throwable error) {
            writeBridgeFailure(report, rootMessage(error));
            show("Read-only product BCD export failed: " + rootMessage(error));
        }
    }

    private static byte[] readFat32File(File image, String... path) throws Exception {
        final long partition = 1_048_576L;
        try (RandomAccessFile raw = new RandomAccessFile(image, "r")) {
            raw.seek(partition); byte[] bpb = new byte[512]; raw.readFully(bpb);
            if (bpb[82] != 'F' || bpb[83] != 'A' || bpb[84] != 'T' || bpb[85] != '3' || bpb[86] != '2') throw new IllegalStateException("Expected FAT32 partition");
            int bps = u16(bpb, 11), spc = bpb[13] & 255, reserved = u16(bpb, 14), fats = bpb[16] & 255;
            long fatSectors = u32(bpb, 36), cluster = u32(bpb, 44), clusterBytes = (long) bps * spc;
            long fat = partition + (long) reserved * bps;
            long data = partition + (reserved + (long) fats * fatSectors) * bps;
            for (int element = 0; element < path.length; ++element) {
                FatEntry entry = findFatEntry(raw, fat, data, clusterBytes, cluster, path[element]);
                if (entry == null) throw new IllegalStateException("FAT entry not found: " + path[element]);
                if (element == path.length - 1) return readFatFile(raw, fat, data, clusterBytes, entry.cluster, entry.size);
                if ((entry.attributes & 0x10) == 0) throw new IllegalStateException("Expected directory: " + path[element]);
                cluster = entry.cluster;
            }
            throw new IllegalStateException("Empty FAT path");
        }
    }

    private static final class FatEntry {
        final long cluster, size; final int attributes;
        FatEntry(long cluster, long size, int attributes) { this.cluster = cluster; this.size = size; this.attributes = attributes; }
    }
    private static FatEntry findFatEntry(RandomAccessFile raw, long fat, long data, long clusterBytes, long start, String wanted) throws Exception {
        for (long cluster : walkFatChain(raw, fat, start)) {
            byte[] directory = new byte[(int) clusterBytes]; raw.seek(data + (cluster - 2) * clusterBytes); raw.readFully(directory);
            String[] longNameParts = new String[21];
            for (int offset = 0; offset < directory.length; offset += 32) {
                int first = directory[offset] & 255;
                if (first == 0) return null;
                if (first == 0xe5) { Arrays.fill(longNameParts, null); continue; }
                if ((directory[offset + 11] & 255) == 0x0f) {
                    int order = directory[offset] & 0x1f;
                    if (order > 0 && order < longNameParts.length) longNameParts[order] = decodeFatLongNamePart(directory, offset);
                    continue;
                }
                String base = new String(directory, offset, 8, java.nio.charset.StandardCharsets.US_ASCII).trim();
                String ext = new String(directory, offset + 8, 3, java.nio.charset.StandardCharsets.US_ASCII).trim();
                String shortName = ext.isEmpty() ? base : base + "." + ext;
                StringBuilder lfn = new StringBuilder();
                for (int i = 1; i < longNameParts.length; ++i) if (longNameParts[i] != null) lfn.append(longNameParts[i]);
                String name = lfn.length() == 0 ? shortName : lfn.toString();
                Arrays.fill(longNameParts, null);
                if (wanted.equalsIgnoreCase(name) || wanted.equalsIgnoreCase(shortName)) {
                    long firstCluster = ((long) u16(directory, offset + 20) << 16) | u16(directory, offset + 26);
                    return new FatEntry(firstCluster, u32(directory, offset + 28), directory[offset + 11] & 255);
                }
            }
        }
        return null;
    }
    private static String decodeFatLongNamePart(byte[] entry, int offset) {
        int[] positions = { 1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30 };
        StringBuilder text = new StringBuilder();
        for (int position : positions) {
            int code = u16(entry, offset + position);
            if (code == 0 || code == 0xffff) break;
            text.append((char) code);
        }
        return text.toString();
    }
    private static long[] walkFatChain(RandomAccessFile raw, long fat, long start) throws Exception {
        java.util.ArrayList<Long> result = new java.util.ArrayList<>();
        java.util.HashSet<Long> seen = new java.util.HashSet<>(); long cluster = start;
        while (cluster >= 2 && cluster < 0x0ffffff8L) {
            if (!seen.add(cluster)) throw new IllegalStateException("FAT loop at " + cluster);
            result.add(cluster); raw.seek(fat + cluster * 4); byte[] next = new byte[4]; raw.readFully(next); cluster = u32(next, 0) & 0x0fffffffL;
        }
        return result.stream().mapToLong(Long::longValue).toArray();
    }
    private static byte[] readFatFile(RandomAccessFile raw, long fat, long data, long clusterBytes, long start, long size) throws Exception {
        if (size > Integer.MAX_VALUE) throw new IllegalStateException("Read-only export is bounded to 2 GiB");
        byte[] result = new byte[(int) size]; int copied = 0;
        for (long cluster : walkFatChain(raw, fat, start)) {
            int take = (int) Math.min(clusterBytes, size - copied); if (take <= 0) break;
            raw.seek(data + (cluster - 2) * clusterBytes); raw.readFully(result, copied, take); copied += take;
        }
        if (copied != size) throw new IllegalStateException("FAT chain shorter than file size");
        return result;
    }

    /**
     * Repeatedly opens only the public app-to-guest vsock endpoint and waits
     * for the agent's 16-byte WVH1 reply. It transmits no keyboard packet.
     */
    private void startVsockHelloProbe(Object vm) {
        new Thread(() -> {
            File report = new File(getExternalFilesDir(null), "vsock-hello-probe-report.txt");
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                out.println("transport=AVF_CONNECT_VSOCK");
                out.println("port=4050");
                Throwable last = null;
                for (int attempt = 1; attempt <= 60; ++attempt) {
                    try {
                        Method connect = vm.getClass().getMethod("connectVsock", long.class);
                        ParcelFileDescriptor pfd = (ParcelFileDescriptor) connect.invoke(vm, 4050L);
                        try (FileInputStream input = new FileInputStream(pfd.getFileDescriptor())) {
                            byte[] hello = new byte[16];
                            int offset = 0;
                            while (offset < hello.length) {
                                int count = input.read(hello, offset, hello.length - offset);
                                if (count < 0) throw new IllegalStateException("short WVH1 reply");
                                offset += count;
                            }
                            if (hello[0] != 'W' || hello[1] != 'V' || hello[2] != 'H' || hello[3] != '1') {
                                throw new IllegalStateException("unexpected vsock hello magic");
                            }
                            long statusCode = ((long) hello[8] & 0xff) | (((long) hello[9] & 0xff) << 8)
                                    | (((long) hello[10] & 0xff) << 16) | (((long) hello[11] & 0xff) << 24);
                            long capabilities = ((long) hello[12] & 0xff) | (((long) hello[13] & 0xff) << 8)
                                    | (((long) hello[14] & 0xff) << 16) | (((long) hello[15] & 0xff) << 24);
                            out.println("attempt=" + attempt);
                            out.println("hello=WVH1");
                            out.println("agentStatus=" + statusCode);
                            out.println("capabilities=" + capabilities);
                            out.println("result=VSOCK_HELLO_PASS");
                            show("VSOCK HELLO received from WinPE agent.");
                            return;
                        } finally {
                            pfd.close();
                        }
                    } catch (Throwable error) {
                        last = error;
                        Thread.sleep(1000);
                    }
                }
                out.println("result=VSOCK_HELLO_NOT_OBSERVED");
                out.println("lastError=" + (last == null ? "none" : rootMessage(last)));
                show("VSOCK HELLO was not observed.");
            } catch (Throwable error) {
                show("VSOCK HELLO probe failed: " + rootMessage(error));
            }
        }, "WinAVF-vsock-hello-probe").start();
    }

    /**
     * Linux-only post-EBS transport proof.  Its disposable initramfs carries
     * a small static AF_VSOCK listener which returns LVH1 on port 4051.  This
     * does not reuse the Windows probe, send input, or touch any Windows file.
     */
    private void startUbuntuVsockHelloProbe(Object vm) {
        new Thread(() -> {
            File report = new File(getExternalFilesDir(null), "ubuntu-gnome-vsock-report.txt");
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                out.println("transport=AVF_CONNECT_VSOCK");
                out.println("guest=UBUNTU_INITRAMFS");
                out.println("port=4051");
                Throwable last = null;
                for (int attempt = 1; attempt <= 90; ++attempt) {
                    try {
                        Method connect = vm.getClass().getMethod("connectVsock", long.class);
                        ParcelFileDescriptor pfd = (ParcelFileDescriptor) connect.invoke(vm, 4051L);
                        try (FileInputStream input = new FileInputStream(pfd.getFileDescriptor())) {
                            byte[] hello = new byte[16];
                            int offset = 0;
                            while (offset < hello.length) {
                                int count = input.read(hello, offset, hello.length - offset);
                                if (count < 0) throw new IllegalStateException("short LVH1 reply");
                                offset += count;
                            }
                            if (hello[0] != 'L' || hello[1] != 'V' || hello[2] != 'H' || hello[3] != '1') {
                                throw new IllegalStateException("unexpected Linux vsock hello magic");
                            }
                            long revision = ((long) hello[4] & 0xff) | (((long) hello[5] & 0xff) << 8)
                                    | (((long) hello[6] & 0xff) << 16) | (((long) hello[7] & 0xff) << 24);
                            long statusCode = ((long) hello[8] & 0xff) | (((long) hello[9] & 0xff) << 8)
                                    | (((long) hello[10] & 0xff) << 16) | (((long) hello[11] & 0xff) << 24);
                            long capabilities = ((long) hello[12] & 0xff) | (((long) hello[13] & 0xff) << 8)
                                    | (((long) hello[14] & 0xff) << 16) | (((long) hello[15] & 0xff) << 24);
                            out.println("attempt=" + attempt);
                            out.println("hello=LVH1");
                            out.println("revision=" + revision);
                            out.println("agentStatus=" + statusCode);
                            out.println("capabilities=" + capabilities);
                            out.println("result=LINUX_VSOCK_HELLO_PASS");
                            show("Ubuntu vsock HELLO received; Linux post-EBS transport is live.");
                            return;
                        } finally {
                            pfd.close();
                        }
                    } catch (Throwable error) {
                        last = error;
                        Thread.sleep(1000);
                    }
                }
                out.println("result=LINUX_VSOCK_HELLO_NOT_OBSERVED");
                out.println("lastError=" + (last == null ? "none" : rootMessage(last)));
                show("Ubuntu vsock HELLO was not observed.");
            } catch (Throwable error) {
                show("Ubuntu vsock probe failed: " + rootMessage(error));
            }
        }, "WinAVF-ubuntu-vsock-hello").start();
    }

    /**
     * Uses the AVF virtio-keyboard endpoint, not the unavailable serial-input
     * endpoint. Linux input-event code 1 is KEY_ESC. The report distinguishes
     * missing API, failed device setup, and accepted press/release writes.
     */
    private void startEscInputProbe(Object vm) {
        new Thread(() -> {
            File report = new File(getExternalFilesDir(null), "uefi-input-probe-report.txt");
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                out.println("transport=AVF_VIRTIO_KEYBOARD");
                out.println("key=KEY_ESC(1)");
                Thread.sleep(1200);
                Method sendKey = vm.getClass().getMethod("sendKeyEvent", short.class, boolean.class);
                boolean down = (Boolean) sendKey.invoke(vm, (short) 1, true);
                Thread.sleep(40);
                boolean up = (Boolean) sendKey.invoke(vm, (short) 1, false);
                out.println("sendKeyEvent=RESOLVED");
                out.println("pressAccepted=" + down);
                out.println("releaseAccepted=" + up);
                out.println("result=" + (down && up ? "HOST_INPUT_ACCEPTED" : "HOST_INPUT_REJECTED"));
                show("UEFI keyboard probe: press=" + down + " release=" + up);
            } catch (Throwable error) {
                try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                    out.println("transport=AVF_VIRTIO_KEYBOARD");
                    out.println("result=HOST_INPUT_ERROR");
                    out.println("error=" + rootMessage(error));
                } catch (Throwable ignored) { }
                show("UEFI keyboard probe failed: " + rootMessage(error));
            }
        }, "WinAVF-esc-input-probe").start();
    }

    private void startSerialEscapeInputProbe(Object vm) {
        new Thread(() -> {
            File report = new File(getExternalFilesDir(null), "uefi-serial-escape-probe-report.txt");
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                out.println("transport=APP_CONSOLE_INPUT_TO_EDK2_SERIAL_CONIN");
                out.println("expectedPrompt=Press ESCAPE for boot options");
                out.println("mode=BOUNDED_PERIODIC_ESC_UNTIL_FIRMWARE_ACK");
                long promptDeadline = System.currentTimeMillis() + 15_000L;
                while (!bootOptionsPromptSeen && System.currentTimeMillis() < promptDeadline) {
                    Thread.sleep(25);
                }
                out.println("promptSeen=" + bootOptionsPromptSeen);
                if (!bootOptionsPromptSeen) {
                    out.println("result=NOT_SENT_PROMPT_NOT_OBSERVED");
                    show("UEFI serial input probe: prompt was not observed; ESC was not sent.");
                    return;
                }
                int before = observedFrameCount;
                OutputStream input = (OutputStream) vm.getClass().getMethod("getConsoleInput").invoke(vm);
                out.println("payloadHex=1B");
                out.println("framesBefore=" + before);
                int writes = 0;
                long sendDeadline = System.currentTimeMillis() + 55_000L;
                while (!serialEscapeAcknowledged && System.currentTimeMillis() < sendDeadline) {
                    input.write(0x1b);
                    input.flush();
                    writes++;
                    Thread.sleep(250L);
                }
                out.println("uartWrites=" + writes);
                out.println("uartWrite=" + (writes > 0 ? "PASS" : "NOT_SENT"));
                show("UEFI serial input probe: bounded ESC stream finished.");
                Thread.sleep(3_000L);
                int after = observedFrameCount;
                out.println("framesAfter=" + after);
                out.println("firmwareEscapeAcknowledged=" + serialEscapeAcknowledged);
                out.println("result=" + (serialEscapeAcknowledged && after > before
                        ? "UEFI_SERIAL_INPUT_AND_GRAPHICS_RESPONSE_PASS"
                        : serialEscapeAcknowledged ? "UEFI_SERIAL_INPUT_PASS_FRAME_NOT_OBSERVED"
                        : "UART_WRITE_PASS_RESPONSE_NOT_OBSERVED"));
            } catch (Throwable error) {
                try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                    out.println("transport=APP_CONSOLE_INPUT_TO_EDK2_SERIAL_CONIN");
                    out.println("result=ERROR");
                    out.println("error=" + rootMessage(error));
                } catch (Throwable ignored) { }
                show("UEFI serial input probe failed: " + rootMessage(error));
            }
        }, "WinAVF-serial-escape-probe").start();
    }

    /** Applies only a self-verifying range bundle to the preserved private copy. */
    private void applyStagedImagePatch(File payload, File image) throws Exception {
        File staging = new File(getExternalFilesDir(null), IMAGE_PATCH_STAGING_NAME);
        File active = new File(payload, IMAGE_PATCH_ACTIVE_NAME);
        if (!staging.isFile()) return;
        if (active.exists()) {
            if (!patchTargetsBaseline(active, image)) {
                throw new IllegalStateException("An earlier image patch is still active; rollback it before applying another patch");
            }
            if (!active.delete()) throw new IllegalStateException("Could not discard the unapplied image patch record");
            show("Discarded a patch record that was never applied to the baseline image.");
        }
        copyFile(staging, active, -1L, true);
        try {
            applyPatch(active, image, false);
            if (!staging.delete()) show("Patch applied; external staging copy could not be deleted.");
            show("Applied verified small image patch: " + active.length() + " bytes");
        } catch (Throwable error) {
            show("Patch was not accepted; active bundle is retained for inspection/rollback.");
            throw error;
        }
    }

    private void rollbackLastPatch() {
        File report = new File(getExternalFilesDir(null), "rollback-report.txt");
        try {
            File payload = new File(getFilesDir(), "payload");
            File image = new File(payload, HEADLESS_BOOT_MEDIA_NAME);
            File active = new File(payload, IMAGE_PATCH_ACTIVE_NAME);
            if (!image.isFile()) throw new IllegalStateException("No app-private runtime image exists yet");
            if (!active.isFile()) throw new IllegalStateException("No active image patch exists to roll back");
            applyPatch(active, image, true);
            if (!active.delete()) throw new IllegalStateException("Rollback passed but the active patch record could not be removed");
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                out.println("RESULT=PASS");
                out.println("BASELINE_SHA256=" + hex(sha256File(image)));
            }
            show("Small image patch rolled back and the runtime image was verified.");
        } catch (Throwable error) {
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                out.println("RESULT=FAIL");
                out.println("ERROR=" + rootMessage(error));
            } catch (Throwable ignored) { }
            show("ROLLBACK FAILED: " + rootMessage(error));
        }
    }

    private static final class PatchRange {
        final long offset, oldDataOffset, newDataOffset;
        final int length;
        final byte[] oldHash, newHash;
        PatchRange(long offset, int length, byte[] oldHash, byte[] newHash, long oldDataOffset, long newDataOffset) {
            this.offset = offset; this.length = length; this.oldHash = oldHash; this.newHash = newHash;
            this.oldDataOffset = oldDataOffset; this.newDataOffset = newDataOffset;
        }
    }

    private static int readLittleEndianInt(RandomAccessFile file) throws Exception {
        int b0 = file.readUnsignedByte(), b1 = file.readUnsignedByte();
        int b2 = file.readUnsignedByte(), b3 = file.readUnsignedByte();
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
    }
    private static long readLittleEndianLong(RandomAccessFile file) throws Exception {
        return (readLittleEndianInt(file) & 0xffffffffL) | ((long) readLittleEndianInt(file) << 32);
    }
    private static boolean patchTargetsBaseline(File patch, File image) throws Exception {
        try (RandomAccessFile bundle = new RandomAccessFile(patch, "r")) {
            byte[] magic = new byte[IMAGE_PATCH_MAGIC.length]; bundle.readFully(magic);
            if (!Arrays.equals(magic, IMAGE_PATCH_MAGIC) || readLittleEndianInt(bundle) != 1) return false;
            if (readLittleEndianLong(bundle) != image.length()) return false;
            byte[] expectedBaseHash = new byte[32]; bundle.readFully(expectedBaseHash);
            return Arrays.equals(expectedBaseHash, sha256File(image));
        }
    }
    private static void applyPatch(File patch, File image, boolean rollback) throws Exception {
        try (RandomAccessFile bundle = new RandomAccessFile(patch, "r")) {
            byte[] magic = new byte[IMAGE_PATCH_MAGIC.length]; bundle.readFully(magic);
            if (!Arrays.equals(magic, IMAGE_PATCH_MAGIC)) throw new IllegalStateException("Unsupported image patch magic");
            if (readLittleEndianInt(bundle) != 1) throw new IllegalStateException("Unsupported image patch version");
            long expectedLength = readLittleEndianLong(bundle);
            if (expectedLength != image.length()) throw new IllegalStateException("Patch targets a different runtime image size");
            byte[] expectedBaseHash = new byte[32]; bundle.readFully(expectedBaseHash);
            int rangeCount = readLittleEndianInt(bundle);
            if (rangeCount < 1 || rangeCount > 4096) throw new IllegalStateException("Invalid image patch range count");
            PatchRange[] ranges = new PatchRange[rangeCount];
            for (int i = 0; i < rangeCount; ++i) {
                long offset = readLittleEndianLong(bundle); int length = readLittleEndianInt(bundle);
                if (offset < 0 || length < 1 || length > 64 * 1024 * 1024 || offset > expectedLength - length) throw new IllegalStateException("Invalid image patch range");
                byte[] oldHash = new byte[32], newHash = new byte[32]; bundle.readFully(oldHash); bundle.readFully(newHash);
                long oldDataOffset = bundle.getFilePointer(); bundle.seek(oldDataOffset + length);
                long newDataOffset = bundle.getFilePointer(); bundle.seek(newDataOffset + length);
                ranges[i] = new PatchRange(offset, length, oldHash, newHash, oldDataOffset, newDataOffset);
            }
            if (bundle.getFilePointer() != bundle.length()) throw new IllegalStateException("Trailing data in image patch");
            if (!rollback && !Arrays.equals(expectedBaseHash, sha256File(image))) throw new IllegalStateException("Runtime image does not match the patch baseline");
            try (RandomAccessFile target = new RandomAccessFile(image, "rw")) {
                for (PatchRange range : ranges) {
                    byte[] expected = rollback ? range.newHash : range.oldHash;
                    byte[] replacementHash = rollback ? range.oldHash : range.newHash;
                    byte[] source = new byte[range.length]; target.seek(range.offset); target.readFully(source);
                    if (!Arrays.equals(expected, sha256(source))) throw new IllegalStateException("Patch range state hash mismatch at " + range.offset);
                    long replacementOffset = rollback ? range.oldDataOffset : range.newDataOffset;
                    byte[] replacement = new byte[range.length]; bundle.seek(replacementOffset); bundle.readFully(replacement);
                    if (!Arrays.equals(replacementHash, sha256(replacement))) throw new IllegalStateException("Patch payload hash mismatch at " + range.offset);
                    target.seek(range.offset); target.write(replacement); target.getFD().sync();
                    target.seek(range.offset); target.readFully(source);
                    if (!Arrays.equals(replacementHash, sha256(source))) throw new IllegalStateException("Patch read-back verification failed at " + range.offset);
                }
            }
            if (rollback && !Arrays.equals(expectedBaseHash, sha256File(image))) throw new IllegalStateException("Rollback did not restore the baseline hash");
        }
    }
    private static byte[] sha256(byte[] bytes) throws Exception { return MessageDigest.getInstance("SHA-256").digest(bytes); }
    private static byte[] sha256File(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256"); byte[] buffer = new byte[1024 * 1024];
        try (InputStream in = new BufferedInputStream(new java.io.FileInputStream(file))) {
            for (int n; (n = in.read(buffer)) >= 0;) digest.update(buffer, 0, n);
        }
        return digest.digest();
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

    private Object buildConfig(File kernel, File esp, boolean enableKeyboardProbe) throws Exception {
        return buildConfig(kernel, esp, enableKeyboardProbe, VM_NAME);
    }

    private Object buildConfig(File kernel, File esp, boolean enableKeyboardProbe, String vmName) throws Exception {
        Class<?> custom = Class.forName("android.system.virtualmachine.VirtualMachineCustomImageConfig");
        Class<?> customBuilder = Class.forName(custom.getName() + "$Builder");
        Object image = customBuilder.getConstructor().newInstance();
        call(image, "setName", String.class, vmName);
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
        if (enableKeyboardProbe) call(image, "useKeyboard", boolean.class, true);
        Class<?> gpuBuilder = Class.forName(custom.getName() + "$GpuConfig$Builder");
        Object gpuConfig = call(gpuBuilder.getConstructor().newInstance(), "build");
        call(image, "setGpuConfig", gpuConfig.getClass(), gpuConfig);

        Object customConfig = call(image, "build");

        Class<?> vmConfig = Class.forName("android.system.virtualmachine.VirtualMachineConfig");
        Class<?> builder = Class.forName(vmConfig.getName() + "$Builder");
        Object config = builder.getConstructor(android.content.Context.class).newInstance(this);
        call(config, "setProtectedVm", boolean.class, false);
        call(config, "setMemoryBytes", long.class, 4L * 1024 * 1024 * 1024);
        call(config, "setCpuTopology", int.class, vmConfig.getField("CPU_TOPOLOGY_ONE_CPU").getInt(null));
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
        startConsoleReader(console, "serial.log");
    }

    private void startConsoleReader(InputStream console, String fileName) {
        new Thread(() -> {
            File serialLog = new File(getExternalFilesDir(null), fileName);
            show("Writing complete VM serial log to " + serialLog.getAbsolutePath());
            try (FileOutputStream rawLog = new FileOutputStream(serialLog, false)) {
                byte[] buffer = new byte[256];
                for (int n; (n = console.read(buffer)) >= 0;) {
                    rawLog.write(buffer, 0, n);
                    rawLog.flush();
                    frameDecoder.feed(buffer, 0, n);
                    String text = new String(buffer, 0, n, java.nio.charset.StandardCharsets.UTF_8);
                    observeUefiBootOptionsPrompt(text);
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

    private void observeUefiBootOptionsPrompt(String text) {
        synchronized (serialProbeTail) {
            serialProbeTail.append(text);
            if (serialProbeTail.length() > 256) {
                serialProbeTail.delete(0, serialProbeTail.length() - 256);
            }
            if (serialProbeTail.indexOf("Press ESCAPE for boot options") >= 0) {
                bootOptionsPromptSeen = true;
            }
            if (serialProbeTail.indexOf("AVF_UEFI_INPUT_WINDOW") >= 0) {
                serialInputWindowSeen = true;
            }
            if (serialProbeTail.indexOf("AVF_UEFI_ESC_RECEIVED") >= 0) {
                serialEscapeAcknowledged = true;
            }
        }
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

    /**
     * Offline reader for the standard Windows Setup witness.  It is invoked
     * only after the VM-owning process was stopped, and opens the app-private
     * disposable disk read-only.  It performs no guest-media writes.
     */
    private void auditPersistentBootWitness() {
        File report = new File(getExternalFilesDir(null), "persistent-boot-witness-report.txt");
        try {
            File payload = new File(getFilesDir(), "payload");
            File disk = new File(payload, HEADLESS_BOOT_MEDIA_NAME);
            if (!disk.isFile() || disk.length() != HEADLESS_BOOT_MEDIA_SIZE) {
                throw new IllegalStateException("No disposable persistent-witness disk is available");
            }
            byte[] setupact = readFatRootFile(disk, "SETUPACT", "LOG", 16 * 1024 * 1024);
            byte[] setuperr = readFatRootFile(disk, "SETUPERR", "LOG", 16 * 1024 * 1024);
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                out.println("scope=POST_STOP_OFFLINE_DISPOSABLE_DISK_INSPECTION");
                out.println("diskBytes=" + disk.length());
                out.println("diskSha256=" + hex(sha256File(disk)));
                boolean found = false;
                if (setupact != null && setupact.length > 0) {
                    File artifact = new File(getExternalFilesDir(null), "persistent-witness-setupact.log");
                    try (FileOutputStream log = new FileOutputStream(artifact, false)) { log.write(setupact); }
                    out.println("SETUPACT_LOG_BYTES=" + setupact.length);
                    out.println("SETUPACT_LOG_SHA256=" + hex(java.security.MessageDigest.getInstance("SHA-256").digest(setupact)));
                    found = true;
                }
                if (setuperr != null && setuperr.length > 0) {
                    File artifact = new File(getExternalFilesDir(null), "persistent-witness-setuperr.log");
                    try (FileOutputStream log = new FileOutputStream(artifact, false)) { log.write(setuperr); }
                    out.println("SETUPERR_LOG_BYTES=" + setuperr.length);
                    out.println("SETUPERR_LOG_SHA256=" + hex(java.security.MessageDigest.getInstance("SHA-256").digest(setuperr)));
                    found = true;
                }
                out.println("PERSISTENT_WINDOWS_SETUP_WITNESS=" + (found ? "PASS" : "NOT_OBSERVED"));
                out.println("WINDOWS_KERNEL_EXECUTION_AFTER_EBS=" + (found ? "PASS" : "NOT_OBSERVED"));
                out.println("NEGATIVE_INTERPRETATION=NO_PERSISTENT_ARTIFACT_DOES_NOT_PROVE_NO_KERNEL_EXECUTION");
            }
            show("Persistent witness offline audit complete");
        } catch (Throwable t) {
            try { writeBridgeFailure(report, rootMessage(t)); } catch (Throwable ignored) { }
            show("Persistent witness audit failed: " + rootMessage(t));
        }
    }

    /** Deletes only the app-private disposable disk and its transaction record. */
    private void cleanupPersistentBootWitness() {
        File report = new File(getExternalFilesDir(null), "persistent-witness-cleanup-report.txt");
        try {
            Object manager = getSystemService((Class) Class.forName("android.system.virtualmachine.VirtualMachineManager"));
            Object vm = manager.getClass().getMethod("get", String.class).invoke(manager, VM_NAME);
            // force-stop terminates execution but the framework can retain the
            // stopped named VM record.  Delete only this known disposable name
            // before opening/deleting its private disk; never touch another VM.
            if (vm != null) {
                manager.getClass().getMethod("delete", String.class).invoke(manager, VM_NAME);
                Object remaining = manager.getClass().getMethod("get", String.class).invoke(manager, VM_NAME);
                if (remaining != null) throw new IllegalStateException("Could not delete stopped diagnostic VM record");
            }
            File payload = new File(getFilesDir(), "payload");
            File privateDisk = new File(payload, HEADLESS_BOOT_MEDIA_NAME);
            File activePatch = new File(payload, IMAGE_PATCH_ACTIVE_NAME);
            if (privateDisk.exists() && !privateDisk.delete()) throw new IllegalStateException("Could not delete disposable private disk");
            if (activePatch.exists() && !activePatch.delete()) throw new IllegalStateException("Could not delete disposable active patch");
            File stagedPatch = new File(getExternalFilesDir(null), IMAGE_PATCH_STAGING_NAME);
            if (stagedPatch.exists() && !stagedPatch.delete()) throw new IllegalStateException("Could not delete external staged patch");
            File immutable = new File(getExternalFilesDir(null), HEADLESS_BOOT_MEDIA_NAME);
            if (!immutable.isFile() || immutable.length() != HEADLESS_BOOT_MEDIA_SIZE) throw new IllegalStateException("Immutable baseline is unavailable");
            String baseline = hex(sha256File(immutable));
            if (!HEADLESS_BOOT_MEDIA_SHA256.equals(baseline)) throw new IllegalStateException("Immutable baseline hash mismatch after cleanup");
            try (PrintWriter out = new PrintWriter(new FileOutputStream(report, false))) {
                out.println("DISPOSABLE_PRIVATE_CLONE_DELETED=PASS");
                out.println("IMMUTABLE_BASELINE_SHA256=" + baseline);
                out.println("RESULT=PASS");
            }
            show("Disposable persistent-witness disk deleted; baseline verified");
        } catch (Throwable t) {
            try { writeBridgeFailure(report, rootMessage(t)); } catch (Throwable ignored) { }
            show("Persistent witness cleanup failed: " + rootMessage(t));
        }
    }

    /** Returns a complete root-level FAT32 file, bounded to a diagnostic size. */
    private static byte[] readFatRootFile(File disk, String wantedName, String wantedExt, int maximumBytes) throws Exception {
        final long partition = 1024L * 1024L;
        try (RandomAccessFile raw = new RandomAccessFile(disk, "r")) {
            byte[] bpb = new byte[512]; raw.seek(partition); raw.readFully(bpb);
            int bps = u16(bpb, 11), spc = bpb[13] & 255, reserved = u16(bpb, 14), fats = bpb[16] & 255;
            long fatSectors = u32(bpb, 36), root = u32(bpb, 44);
            if (bps != 512 || spc == 0 || fats != 2 || root < 2) throw new IllegalStateException("Unexpected FAT32 geometry");
            long fat = partition + (long) reserved * bps;
            long data = partition + (long) (reserved + fats * fatSectors) * bps;
            int clusterBytes = bps * spc;
            long cluster = root;
            for (int guard = 0; guard < 1024 && cluster >= 2 && cluster < 0x0ffffff8L; ++guard) {
                byte[] directory = new byte[clusterBytes]; raw.seek(data + (cluster - 2) * clusterBytes); raw.readFully(directory);
                for (int off = 0; off + 32 <= directory.length; off += 32) {
                    if (directory[off] == 0) return null;
                    if ((directory[off] & 255) == 0xe5 || (directory[off + 11] & 255) == 0x0f || (directory[off + 11] & 0x10) != 0) continue;
                    String name = new String(directory, off, 8, java.nio.charset.StandardCharsets.US_ASCII).trim();
                    String ext = new String(directory, off + 8, 3, java.nio.charset.StandardCharsets.US_ASCII).trim();
                    if (!wantedName.equals(name) || !wantedExt.equals(ext)) continue;
                    long first = ((long) u16(directory, off + 20) << 16) | u16(directory, off + 26);
                    long size = u32(directory, off + 28);
                    if (size <= 0 || size > maximumBytes) throw new IllegalStateException("Witness log has invalid or excessive size: " + size);
                    byte[] output = new byte[(int) size]; int copied = 0;
                    for (int chainGuard = 0; chainGuard < 4096 && first >= 2 && first < 0x0ffffff8L && copied < size; ++chainGuard) {
                        int take = Math.min(clusterBytes, (int) size - copied);
                        raw.seek(data + (first - 2) * clusterBytes); raw.readFully(output, copied, take); copied += take;
                        byte[] next = new byte[4]; raw.seek(fat + first * 4); raw.readFully(next); first = u32(next, 0) & 0x0fffffffL;
                    }
                    if (copied != size) throw new IllegalStateException("Witness FAT chain ended before file size");
                    return output;
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
    private void show(String message) {
        runOnUiThread(() -> {
            String stamp = new java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ROOT)
                    .format(new java.util.Date());
            uiLog.append(stamp).append("  ").append(message).append('\n');
            // Keep the on-screen history bounded even during a long serial run.
            if (uiLog.length() > 24 * 1024) uiLog.delete(0, uiLog.length() - 24 * 1024);
            status.setText(message);
            if (!frameVisible) status.setVisibility(View.VISIBLE);
            if (logPanel != null && logPanel.getVisibility() == View.VISIBLE) refreshLogPanel();
        });
    }
    private static String rootMessage(Throwable error) {
        while (error.getCause() != null) error = error.getCause();
        return error.getClass().getSimpleName() + ": " + error.getMessage();
    }
}

package com.uthman.phonelink;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Flash-launch clipboard relay. PhoneLink spawns it via
 * `adb shell am start` with `--es mode read|write`, it does its thing on a
 * transparent invisible window, writes the result into its own external files
 * dir (adb can read/write that path), and finishes.
 *
 * Verified on itel A663LC (Android 13): writes land (real paste proof);
 * reads return empty inside onResume but succeed once the window settles,
 * hence the delayed read below.
 */
public class PhoneRelayActivity extends Activity {
    // resolved via API — raw /sdcard paths are FUSE-blocked on this ROM even
    // for the app's own dir; getExternalFilesDir always resolves correctly
    static String dirPath;
    static final String TAG = "RELAY";

    @Override protected void onCreate(android.os.Bundle b) {
        super.onCreate(b);
        // NOTE: FLAG_SHOW_WHEN_LOCKED/TURN_SCREEN_ON were tried and BROKE
        // clipboard writes on this ROM (selfcheck read back empty) — the
        // plain explicit-launch window is what works. Screen wake happens
        // on the adb side (input keyevent 224) before flashing.
    }

    @Override protected void onResume() {
        super.onResume();
        try {
            File dir = getExternalFilesDir(null);
            dirPath = dir != null ? dir.getAbsolutePath() : "/sdcard/Android/data/com.uthman.phonelink/files";
            new File(dirPath).mkdirs();
            Intent i = getIntent();
            String mode = i.getStringExtra("mode");
            if ("write".equals(mode)) doWrite(i);
            else doRead();
        } catch (Exception e) {
            Log.e(TAG, "flash failed", e);
        }
        finish();
    }

    // diagnostics: write then delayed-read IN THE SAME PROCESS — isolates whether
    // our own writes land and re-read (the only combo ever seen working)
    // mirror com.test.clip's winning shape: initial getPrimaryClip, then write,
    // then delayed re-read — tests whether the flash SHAPE grants clip persistence




    // ---- write: setPrimaryClip from --es text, or from files/in.txt (pushed by the module) ----
    private void doWrite(Intent i) throws Exception {
        String text = i.getStringExtra("text");
        if (text == null) {
            File f = new File(dirPath, "in.txt");
            if (f.exists()) text = readFile(f);
        }
        if (text == null || text.length() == 0) {
            save("ack.txt", "EMPTY");
            return;
        }
        ClipboardManager cm = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        cm.setPrimaryClip(ClipData.newPlainText("PhoneRelay", text));
        save("ack.txt", "OK");
        new File(dirPath, "in.txt").delete();
    }

    // ---- read: wait for the window to settle, then grab ----
    private void doRead() {
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            try {
                ClipboardManager cm = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                String out = "";
                if (cm.hasPrimaryClip()) {
                    ClipData cd = cm.getPrimaryClip();
                    if (cd != null && cd.getItemCount() > 0) {
                        CharSequence t = cd.getItemAt(0).coerceToText(this);
                        if (t != null) out = t.toString();
                    }
                }
                save("clip.txt", out);
            } catch (Exception e) {
                Log.e(TAG, "read failed", e);
            }
            finish();
        }, 1500);
    }

    // ---- files ----
    static String readFile(File f) throws Exception {
        byte[] b = new byte[(int) f.length()];
        try (java.io.FileInputStream in = new java.io.FileInputStream(f)) {
            int off = 0, n;
            while (off < b.length && (n = in.read(b, off, b.length - off)) > 0) off += n;
        }
        return new String(b, StandardCharsets.UTF_8);
    }

    static void save(String name, String content) {
        try (FileOutputStream out = new FileOutputStream(new File(dirPath, name))) {
            out.write(content.getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            Log.e(TAG, "cannot write " + name, e);
        }
    }
}
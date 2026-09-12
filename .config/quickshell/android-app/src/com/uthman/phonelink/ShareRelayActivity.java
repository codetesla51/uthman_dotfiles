package com.uthman.phonelink;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;
import android.widget.Toast;

import java.io.InputStream;
import java.io.OutputStream;

/**
 * Share-sheet target. Anything shared from a phone app lands in
 * Download/PhoneLinkInbox/ via MediaStore (no storage permission needed on
 * API 29+), where the PhoneLink pull browser can pick it up over adb.
 */
public class ShareRelayActivity extends Activity {
    static final String TAG = "RELAY";
    static final String INBOX = Environment.DIRECTORY_DOWNLOADS + "/PhoneLinkInbox";

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        try {
            Intent i = getIntent();
            if (Intent.ACTION_SEND.equals(i.getAction())) handleSend(i);
        } catch (Exception e) {
            Log.e(TAG, "share failed", e);
            Toast.makeText(this, "Share failed: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
        finish();
    }

    private void handleSend(Intent i) throws Exception {
        ContentResolver cr = getContentResolver();
        Uri stream = i.getParcelableExtra(Intent.EXTRA_STREAM);
        String ts = String.valueOf(System.currentTimeMillis());
        if (stream != null) {
            String name = "phonelink-" + ts + "-" + fileNameOf(cr, stream);
            ContentValues cv = new ContentValues();
            cv.put(MediaStore.Downloads.DISPLAY_NAME, name);
            cv.put(MediaStore.Downloads.MIME_TYPE, i.getType() != null ? i.getType() : "*/*");
            cv.put(MediaStore.Downloads.RELATIVE_PATH, INBOX);
            Uri out = cr.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv);
            try (InputStream in = cr.openInputStream(stream);
                 OutputStream os = cr.openOutputStream(out)) {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) > 0) os.write(buf, 0, n);
            }
            Log.d(TAG, "file share landed: " + name);
            Toast.makeText(this, "Saved to Download/PhoneLinkInbox/", Toast.LENGTH_LONG).show();
        } else {
            String subj = i.getStringExtra(Intent.EXTRA_SUBJECT);
            String text = i.getStringExtra(Intent.EXTRA_TEXT);
            String body = "";
            if (text != null) body += text;
            if (subj != null) body = body + (body.length() > 0 ? "\n\n" : "") + subj;
            if (body.trim().length() == 0) body = "(empty share)";
            ContentValues cv = new ContentValues();
            cv.put(MediaStore.Downloads.DISPLAY_NAME, "phonelink-" + ts + ".txt");
            cv.put(MediaStore.Downloads.MIME_TYPE, "text/plain");
            cv.put(MediaStore.Downloads.RELATIVE_PATH, INBOX);
            Uri out = cr.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv);
            try (OutputStream os = cr.openOutputStream(out)) {
                os.write(body.getBytes("UTF-8"));
            }
            Log.d(TAG, "text share landed: " + body.length() + " chars");
            Toast.makeText(this, "Saved to Download/PhoneLinkInbox/", Toast.LENGTH_LONG).show();
        }
    }

    private static String fileNameOf(ContentResolver cr, Uri uri) {
        try (Cursor c = cr.query(uri, new String[]{MediaStore.MediaColumns.DISPLAY_NAME}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                String n = c.getString(0);
                if (n != null && n.length() > 0) return sanitize(n);
            }
        } catch (Exception ignored) {}
        String p = uri.getLastPathSegment();
        return p != null ? sanitize(p) : "file";
    }

    private static String sanitize(String n) {
        String s = n.replaceAll("[^A-Za-z0-9._-]", "_");
        return s.length() > 0 ? s : "file";
    }
}
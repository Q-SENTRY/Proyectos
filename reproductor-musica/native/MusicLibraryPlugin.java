package com.qsentry.reproductor;

import android.Manifest;
import android.content.ContentResolver;
import android.content.ContentUris;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import android.util.Base64;
import android.util.Size;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;

@CapacitorPlugin(
    name = "MusicLibrary",
    permissions = {
        @Permission(alias = "audio", strings = { Manifest.permission.READ_MEDIA_AUDIO }),
        @Permission(alias = "storage", strings = { Manifest.permission.READ_EXTERNAL_STORAGE })
    }
)
public class MusicLibraryPlugin extends Plugin {

    static MusicLibraryPlugin instance;

    @Override
    public void load() { instance = this; }

    /** Llamado por el widget cuando se toca un botón. */
    void fromWidget(String action) {
        JSObject d = new JSObject();
        d.put("action", action);
        notifyListeners("widget", d, true);
    }

    @PluginMethod
    public void updateWidget(PluginCall call) {
        android.content.SharedPreferences.Editor e = getContext().getSharedPreferences(PlayerWidget.PREFS, android.content.Context.MODE_PRIVATE).edit();
        e.putString("title", call.getString("title", ""));
        e.putString("artist", call.getString("artist", ""));
        e.putBoolean("playing", Boolean.TRUE.equals(call.getBoolean("playing", false)));
        String art = call.getString("art");
        if (art != null && art.startsWith("data:")) {
            try {
                String b64 = art.substring(art.indexOf(",") + 1);
                byte[] raw = Base64.decode(b64, Base64.DEFAULT);
                Bitmap b = BitmapFactory.decodeByteArray(raw, 0, raw.length);
                if (b != null) {
                    Bitmap sc = Bitmap.createScaledBitmap(b, 200, 200, true);
                    java.io.File f = new java.io.File(getContext().getFilesDir(), "widget_art.png");
                    try (java.io.FileOutputStream out = new java.io.FileOutputStream(f)) { sc.compress(Bitmap.CompressFormat.PNG, 100, out); }
                    e.putBoolean("hasArt", true);
                }
            } catch (Exception ignored) { e.putBoolean("hasArt", false); }
        }
        e.apply();
        int n = PlayerWidget.renderAll(getContext());
        JSObject r = new JSObject();
        r.put("widgets", n);
        call.resolve(r);
    }

    private String alias() { return Build.VERSION.SDK_INT >= 33 ? "audio" : "storage"; }
    private boolean granted() { return getPermissionState(alias()) == PermissionState.GRANTED; }

    @PluginMethod
    public void status(PluginCall call) {
        JSObject r = new JSObject();
        r.put("granted", granted());
        call.resolve(r);
    }

    @PluginMethod
    public void scan(PluginCall call) {
        if (!granted()) { requestPermissionForAlias(alias(), call, "permissionCallback"); return; }
        doScan(call);
    }

    @PermissionCallback
    private void permissionCallback(PluginCall call) {
        if (granted()) { doScan(call); return; }
        JSObject r = new JSObject();
        r.put("granted", false);
        r.put("songs", new JSArray());
        call.resolve(r);
    }

    private void doScan(PluginCall call) {
        new Thread(() -> {
            Uri col = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
            String[] proj = {
                MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.ALBUM_ID, MediaStore.Audio.Media.DURATION,
                MediaStore.Audio.Media.DATE_ADDED
            };
            String sel = MediaStore.Audio.Media.IS_MUSIC + " != 0";
            JSArray songs = new JSArray();
            try (Cursor c = getContext().getContentResolver().query(col, proj, sel, null,
                    MediaStore.Audio.Media.TITLE + " COLLATE NOCASE ASC")) {
                if (c != null) {
                    while (c.moveToNext()) {
                        long id = c.getLong(0);
                        JSObject s = new JSObject();
                        s.put("id", String.valueOf(id));
                        s.put("title", c.getString(1));
                        String artist = c.getString(2);
                        s.put("artist", artist == null || artist.equals("<unknown>") ? "" : artist);
                        s.put("album", c.getString(3));
                        s.put("albumId", c.getLong(4));
                        s.put("duration", c.getLong(5));
                        s.put("added", c.getLong(6));
                        s.put("uri", ContentUris.withAppendedId(col, id).toString());
                        songs.put(s);
                    }
                }
                JSObject r = new JSObject();
                r.put("granted", true);
                r.put("songs", songs);
                call.resolve(r);
            } catch (Exception e) {
                call.reject("Error al leer la música: " + e.getMessage());
            }
        }).start();
    }

    @PluginMethod
    public void artwork(PluginCall call) {
        String uri = call.getString("uri");
        long albumId = call.getLong("albumId", -1L);
        new Thread(() -> {
            JSObject r = new JSObject();
            try {
                ContentResolver cr = getContext().getContentResolver();
                Bitmap b = null;
                if (Build.VERSION.SDK_INT >= 29 && uri != null) {
                    try { b = cr.loadThumbnail(Uri.parse(uri), new Size(256, 256), null); } catch (Exception ignored) {}
                }
                if (b == null && albumId >= 0) {
                    Uri art = ContentUris.withAppendedId(Uri.parse("content://media/external/audio/albumart"), albumId);
                    try (InputStream in = cr.openInputStream(art)) { if (in != null) b = BitmapFactory.decodeStream(in); } catch (Exception ignored) {}
                }
                if (b != null) {
                    Bitmap s = Bitmap.createScaledBitmap(b, 256, 256, true);
                    ByteArrayOutputStream out = new ByteArrayOutputStream();
                    s.compress(Bitmap.CompressFormat.JPEG, 82, out);
                    r.put("data", "data:image/jpeg;base64," + Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP));
                }
            } catch (Exception ignored) {}
            call.resolve(r);
        }).start();
    }
}

package com.qsentry.reproductor;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.widget.RemoteViews;

import java.io.File;

/** Widget de pantalla de inicio: carátula, título, artista y controles. */
public class PlayerWidget extends AppWidgetProvider {

    static final String PREFS = "player_widget";
    static final String ACTION = "com.qsentry.reproductor.WIDGET";

    @Override
    public void onUpdate(Context ctx, AppWidgetManager mgr, int[] ids) { renderAll(ctx); }

    @Override
    public void onReceive(Context ctx, Intent intent) {
        super.onReceive(ctx, intent);
        if (!ACTION.equals(intent.getAction())) return;
        String action = intent.getStringExtra("a");
        MusicLibraryPlugin p = MusicLibraryPlugin.instance;
        if (p != null && p.getBridge() != null && p.getActivity() != null && !p.getActivity().isDestroyed()) {
            p.fromWidget(action);
        } else {
            // La app no está abierta: la abrimos
            Intent open = new Intent(ctx, MainActivity.class);
            open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            ctx.startActivity(open);
        }
    }

    private static PendingIntent action(Context ctx, String a, int code) {
        Intent i = new Intent(ctx, PlayerWidget.class).setAction(ACTION).putExtra("a", a);
        return PendingIntent.getBroadcast(ctx, code, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    static int renderAll(Context ctx) {
        AppWidgetManager mgr = AppWidgetManager.getInstance(ctx);
        int[] ids = mgr.getAppWidgetIds(new ComponentName(ctx, PlayerWidget.class));
        if (ids.length == 0) return 0;
        SharedPreferences sp = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        RemoteViews v = new RemoteViews(ctx.getPackageName(), R.layout.widget_player);
        String title = sp.getString("title", "");
        v.setTextViewText(R.id.w_title, title.isEmpty() ? "Reproductor" : title);
        v.setTextViewText(R.id.w_artist, title.isEmpty() ? "Toca para abrir" : sp.getString("artist", ""));
        v.setImageViewResource(R.id.w_play, sp.getBoolean("playing", false) ? R.drawable.ic_w_pause : R.drawable.ic_w_play);
        Bitmap art = null;
        if (sp.getBoolean("hasArt", false)) {
            File f = new File(ctx.getFilesDir(), "widget_art.png");
            if (f.exists()) art = BitmapFactory.decodeFile(f.getAbsolutePath());
        }
        if (art != null) v.setImageViewBitmap(R.id.w_art, art); else v.setImageViewResource(R.id.w_art, R.drawable.widget_art_placeholder);
        v.setOnClickPendingIntent(R.id.w_prev, action(ctx, "prev", 1));
        v.setOnClickPendingIntent(R.id.w_play, action(ctx, "toggle", 2));
        v.setOnClickPendingIntent(R.id.w_next, action(ctx, "next", 3));
        Intent open = new Intent(ctx, MainActivity.class);
        v.setOnClickPendingIntent(R.id.w_root, PendingIntent.getActivity(ctx, 4, open, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
        mgr.updateAppWidget(ids, v);
        return ids.length;
    }
}

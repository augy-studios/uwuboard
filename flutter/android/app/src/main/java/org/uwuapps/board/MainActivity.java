package org.uwuapps.board;

import android.Manifest;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.ActivityNotFoundException;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.provider.Settings;
import android.util.Base64;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.FirebaseMessaging;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * The app's one window, and the bridge to the Dart side (lib/native/bridge.dart): one method
 * channel, whose "call" names a plugin and a method and carries its options as JSON, answered
 * with JSON. There is one plugin, App:
 *
 *   info          the version, and what this build can do (features)
 *   launchLink    the link the app was opened with, once
 *   saveFile      a file into Downloads
 *   installApk    a downloaded update, to Android's installer (the GitHub APK only)
 *   setReleases   joins or leaves the Firebase topic for new versions (FIREBASE-SETUP.md)
 *   openSettings  the app's notification settings
 *   keepScreenOn  while a sync runs
 *   background    Back's second press: to the background, not closed
 *
 * And its events: "link" for a link arriving while the app runs, "openUpdates" for a tapped
 * notification of a new version.
 */
public class MainActivity extends FlutterActivity {
    static final String CHANNEL = "org.uwuapps.board/bridge";
    static final String RELEASES_TOPIC = "uwuboard-releases";
    static final String OPEN_UPDATES = "org.uwuapps.board.OPEN_UPDATES";
    private static final int ASK_NOTIFICATIONS = 41;

    private MethodChannel channel;
    private String launchLink;
    private MethodChannel.Result pendingReleases;
    private boolean pendingReleasesOn;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Notifications.channels(this);
        launchLink = linkOf(getIntent());
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this::onCall);
    }

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String link = linkOf(intent);
        if (link == null) return;
        Map<String, Object> data = new HashMap<>();
        data.put("url", link);
        emit("link", data);
    }

    /** The app's own address for what an intent asks: a link, or the Updates page. */
    private static String linkOf(Intent intent) {
        if (intent == null) return null;
        if (OPEN_UPDATES.equals(intent.getAction())) return "uwu://board/updates";
        // A notification Firebase showed itself carries its data as extras.
        if ("release".equals(intent.getStringExtra("type"))) return "uwu://board/updates";
        Uri data = intent.getData();
        if (Intent.ACTION_VIEW.equals(intent.getAction()) && data != null) return data.toString();
        return null;
    }

    private void emit(String event, Map<String, Object> data) {
        if (channel == null) return;
        Map<String, Object> args = new HashMap<>();
        args.put("plugin", "App");
        args.put("event", event);
        args.put("data", new JSONObject(data).toString());
        new Handler(Looper.getMainLooper()).post(() -> channel.invokeMethod("event", args));
    }

    private void onCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "hello":
            case "listen":
            case "unlisten":
                result.success(null);
                return;
            case "call":
                break;
            default:
                result.notImplemented();
                return;
        }
        String plugin = call.argument("plugin");
        String method = call.argument("method");
        JSONObject options;
        try {
            String raw = call.argument("options");
            options = new JSONObject(raw == null ? "{}" : raw);
        } catch (Exception e) {
            options = new JSONObject();
        }
        if (!"App".equals(plugin)) {
            result.error("unavailable", "No plugin " + plugin, null);
            return;
        }
        try {
            app(method, options, result);
        } catch (Exception e) {
            result.error("failed", e.getMessage(), null);
        }
    }

    private static void ok(MethodChannel.Result result, JSONObject answer) {
        result.success(answer == null ? null : answer.toString());
    }

    private boolean firebaseReady() {
        try {
            return !FirebaseApp.getApps(this).isEmpty();
        } catch (Throwable t) {
            return false;
        }
    }

    private void app(String method, JSONObject o, MethodChannel.Result result) throws Exception {
        switch (method) {
            case "info": {
                JSONArray features = new JSONArray();
                features.put("saveFile");
                features.put("links");
                if (!BuildConfig.PLAY) features.put("update");
                if (firebaseReady()) features.put("push");
                JSONObject a = new JSONObject();
                a.put("platform", "android");
                a.put("version", BuildConfig.VERSION_NAME);
                a.put("build", BuildConfig.VERSION_CODE);
                a.put("play", BuildConfig.PLAY);
                a.put("sdk", Build.VERSION.SDK_INT);
                // For a bug report (lib/features/bug/bug_report.dart): "Android 14 · Google Pixel 8".
                a.put("release", Build.VERSION.RELEASE);
                a.put("model", (Build.MANUFACTURER + " " + Build.MODEL).trim());
                a.put("features", features);
                ok(result, a);
                return;
            }
            case "launchLink": {
                JSONObject a = new JSONObject();
                if (launchLink != null) a.put("url", launchLink);
                launchLink = null;
                ok(result, a);
                return;
            }
            case "saveFile":
                saveFile(o, result);
                return;
            case "installApk":
                installApk(o, result);
                return;
            case "setReleases":
                setReleases(o.optBoolean("on"), result);
                return;
            case "openSettings": {
                Intent i = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName());
                try {
                    startActivity(i);
                } catch (ActivityNotFoundException e) {
                    startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName())));
                }
                ok(result, null);
                return;
            }
            case "keepScreenOn":
                if (o.optBoolean("on")) getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                else getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                ok(result, null);
                return;
            case "background":
                moveTaskToBack(true);
                ok(result, new JSONObject());
                return;
            default:
                result.error("unavailable", "No method " + method, null);
        }
    }

    /** Into Downloads: MediaStore from Android 10 (no permission), the folder itself before. */
    private void saveFile(JSONObject o, MethodChannel.Result result) throws Exception {
        String name = o.optString("name", "uwuboard-file");
        String mime = o.optString("mime", "application/octet-stream");
        byte[] bytes = Base64.decode(o.optString("data", ""), Base64.DEFAULT);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContentResolver resolver = getContentResolver();
            ContentValues values = new ContentValues();
            values.put(MediaStore.Downloads.DISPLAY_NAME, name);
            values.put(MediaStore.Downloads.MIME_TYPE, mime);
            values.put(MediaStore.Downloads.IS_PENDING, 1);
            Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (uri == null) throw new IllegalStateException("Couldn't make the file");
            try (OutputStream out = resolver.openOutputStream(uri)) {
                if (out == null) throw new IllegalStateException("Couldn't write the file");
                out.write(bytes);
            }
            values.clear();
            values.put(MediaStore.Downloads.IS_PENDING, 0);
            resolver.update(uri, values, null, null);
        } else {
            File dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
            if (!dir.exists() && !dir.mkdirs()) dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
            try (FileOutputStream out = new FileOutputStream(new File(dir, name))) {
                out.write(bytes);
            }
        }
        JSONObject a = new JSONObject();
        a.put("path", "Downloads/" + name);
        ok(result, a);
    }

    /** A downloaded, checked APK to Android's installer, once installing from this app is allowed. */
    private void installApk(JSONObject o, MethodChannel.Result result) {
        if (BuildConfig.PLAY) {
            result.error("unavailable", "Google Play updates this app", null);
            return;
        }
        File apk = new File(o.optString("path"));
        if (!apk.exists()) {
            result.error("failed", "The download is gone", null);
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !getPackageManager().canRequestPackageInstalls()) {
            startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + getPackageName())));
            result.error("permission", "Allow installing apps from uwuBoard", null);
            return;
        }
        Uri uri = FileProvider.getUriForFile(this, getPackageName() + ".files", apk);
        Intent i = new Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(i);
        ok(result, null);
    }

    /** Joins or leaves the release topic; turning it on asks for notifications first (Android 13+). */
    private void setReleases(boolean on, MethodChannel.Result result) {
        if (!firebaseReady()) {
            result.error("unavailable", "Built without Firebase", null);
            return;
        }
        if (on && Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            pendingReleases = result;
            pendingReleasesOn = true;
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, ASK_NOTIFICATIONS);
            return;
        }
        subscribe(on, result);
    }

    private void subscribe(boolean on, MethodChannel.Result result) {
        FirebaseMessaging fm = FirebaseMessaging.getInstance();
        (on ? fm.subscribeToTopic(RELEASES_TOPIC) : fm.unsubscribeFromTopic(RELEASES_TOPIC))
                .addOnCompleteListener(task -> {
                    if (task.isSuccessful()) ok(result, null);
                    else result.error("network", "Couldn't reach Firebase", null);
                });
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grants) {
        super.onRequestPermissionsResult(requestCode, permissions, grants);
        if (requestCode != ASK_NOTIFICATIONS || pendingReleases == null) return;
        MethodChannel.Result result = pendingReleases;
        pendingReleases = null;
        if (grants.length > 0 && grants[0] == PackageManager.PERMISSION_GRANTED) subscribe(pendingReleasesOn, result);
        else result.error("permission", "Notifications are off for uwuBoard", null);
    }

    /** The app's notification channels, made once. */
    static final class Notifications {
        static void channels(android.content.Context context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
            NotificationManager nm = context.getSystemService(NotificationManager.class);
            if (nm == null) return;
            NotificationChannel releases = new NotificationChannel("releases", "New versions of the app", NotificationManager.IMPORTANCE_DEFAULT);
            releases.setDescription("When a new version of uwuBoard is out");
            nm.createNotificationChannel(releases);
        }
    }
}

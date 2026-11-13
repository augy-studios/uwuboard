package org.uwuapps.board;

import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import java.util.Map;

/**
 * "uwuBoard 1.0.1 is out" from the site (main-site/api/push/release.js), on the uwuboard-releases
 * topic the Updates page's switch joins. While the app's in the background Android shows it
 * itself, from the message's notification; this shows it while the app's in front, where Android
 * wouldn't. Either way, tapping it opens the Updates page.
 */
public class MessagingService extends FirebaseMessagingService {
    @Override
    public void onMessageReceived(@NonNull RemoteMessage message) {
        Map<String, String> data = message.getData();
        if (!"release".equals(data.get("type"))) return;
        MainActivity.Notifications.channels(this);
        String title = data.get("title");
        String body = data.get("body");
        Intent open = new Intent(MainActivity.OPEN_UPDATES)
                .setPackage(getPackageName())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        PendingIntent tap = PendingIntent.getActivity(this, 1, open, flags);
        NotificationCompat.Builder n = new NotificationCompat.Builder(this, "releases")
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title == null ? "A new version of uwuBoard is out" : title)
                .setContentText(body == null ? "" : body)
                .setAutoCancel(true)
                .setContentIntent(tap);
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm != null) nm.notify("release", 1, n.build());
    }

    @Override
    public void onNewToken(@NonNull String token) {
        // Topics need no token kept on the server.
    }
}

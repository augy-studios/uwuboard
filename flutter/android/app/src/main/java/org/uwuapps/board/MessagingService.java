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
        if (!"release".equals(data.get("type"))) {
            return;
        }
        MainActivity.Notifications.channels(this);
        String title = data.get("title");
        String body = data.get("body");
        // Tapping the notification opens the Updates page.
        Intent openUpdatesIntent = new Intent(MainActivity.OPEN_UPDATES)
                .setPackage(getPackageName())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        int immutableFlag;
        if (Build.VERSION.SDK_INT >= 23) {
            immutableFlag = PendingIntent.FLAG_IMMUTABLE;
        } else {
            immutableFlag = 0;
        }
        int pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT | immutableFlag;
        PendingIntent tapIntent = PendingIntent.getActivity(this, 1, openUpdatesIntent, pendingIntentFlags);
        // The message's own title and text, or a plain title and no text when it has none.
        String contentTitle;
        if (title == null) {
            contentTitle = "A new version of uwuBoard is out";
        } else {
            contentTitle = title;
        }
        String contentText;
        if (body == null) {
            contentText = "";
        } else {
            contentText = body;
        }
        NotificationCompat.Builder notificationBuilder = new NotificationCompat.Builder(this, "releases")
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(contentTitle)
                .setContentText(contentText)
                .setAutoCancel(true)
                .setContentIntent(tapIntent);
        NotificationManager notificationManager = getSystemService(NotificationManager.class);
        if (notificationManager != null) {
            notificationManager.notify("release", 1, notificationBuilder.build());
        }
    }

    @Override
    public void onNewToken(@NonNull String token) {
        // Topics need no token kept on the server.
    }
}

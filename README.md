# push_notification_manger

A reusable Flutter push notification manager built on top of Firebase Cloud Messaging and `flutter_local_notifications`.

## Features

- Single initialization for push handling
- Unified payload model (`PushNotificationPayload`)
- Handles notification states:
  - Foreground (`FirebaseMessaging.onMessage`)
  - Background open (`FirebaseMessaging.onMessageOpenedApp`)
  - Terminated/killed app launch (`FirebaseMessaging.getInitialMessage`)
  - Background message entry point (`FirebaseMessaging.onBackgroundMessage`)
- Local notification tap payload parsing
- Token fetch + token refresh callback
- Notification lifecycle event hook (`onNotificationEvent`)
- De-duplication window for repeated payloads
- Listener lifecycle cleanup via `PushNotificationManager.dispose()`
- Topic subscription helpers:
  - `subscribeToTopic`
  - `unsubscribeFromTopic`
  - `subscribeToTopics`
  - `unsubscribeFromTopics`

## Getting started

Add dependencies in your app:

```yaml
dependencies:
  firebase_core: ^3.13.1
  firebase_messaging: ^15.2.6
  flutter_local_notifications: ^19.2.1
  push_notification_manger: ^0.1.1
```

Then complete Firebase setup for iOS/Android in your app project (Firebase console + platform files).

## Usage

Initialize once (for example in app startup):

```dart
import 'package:push_notification_manger/push_notification_manger.dart';

Future<void> setupPush() async {
  await PushNotificationManager.init(
    config: const PushNotificationConfig(
      channelId: 'general_notifications',
      channelName: 'General Notifications',
      channelDescription: 'General app updates',
      androidSmallIcon: '@mipmap/ic_launcher',
      handleForeground: true,
      showForegroundLocalNotificationOnIOS: false,
      processForegroundPayloadImmediately: true,
      requestProvisionalPermission: false,
      deduplicationWindow: Duration(minutes: 2),
    ),
    onBackgroundMessage: firebaseMessagingBackgroundHandler,
    onTokenUpdated: (String token) async {
      // Save token to backend/shared preference
    },
    onPayloadReceived: (PushNotificationPayload payload) async {
      // Handle navigation or action
      // Example: payload.type, payload.action, payload.data
    },
    onNotificationEvent: (NotificationEvent event) async {
      // Optional: analytics/monitoring (received/displayed/tapped/failed)
    },
  );
}
```

Top-level background handler (required by Firebase):

```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Do lightweight background work here.
}
```

### Platform behavior

- Foreground local notification rendering is shown on Android when `handleForeground: true`.
- iOS foreground local rendering can be enabled with `showForegroundLocalNotificationOnIOS: true`.
- On iOS, foreground presentation is controlled by `setForegroundNotificationPresentationOptions` and APNs delivery behavior.
- Open/tap/terminated flows are handled on both Android and iOS.

### Topic subscription

```dart
await PushNotificationManager.subscribeToTopic('news');
await PushNotificationManager.subscribeToTopics(['offers', 'reminders']);

await PushNotificationManager.unsubscribeFromTopic('news');
await PushNotificationManager.unsubscribeFromTopics(['offers', 'reminders']);
```

### Payload handling notes

- Use `payload.data` for your custom keys.
- Use `payload.type`/`payload.action` for routing decisions.
- Local notification tap payload is parsed through the same model for consistency.
- Duplicate payloads are ignored within `deduplicationWindow`.
- Use `PushNotificationManager.dispose()` if you need to reset/reinitialize listeners.

### Production initialization pattern

- Call `PushNotificationManager.init(...)` once during app startup.
- Pass a top-level `onBackgroundMessage` function with `@pragma('vm:entry-point')`.
- Keep heavy work out of background handler; queue/sync later if needed.
- Use `onNotificationEvent` to monitor delivery/tap/failure signals.

## Example app

A runnable demo is available in `example/`:

- `example/lib/main.dart` shows:
  - init with callbacks
  - topic subscribe/unsubscribe buttons
  - payload-based routing decisions for `chat`, `order`, and `promo`

Sample payload data:

```json
{
  "type": "chat",
  "chatId": "123",
  "senderId": "42"
}
```

## Additional information

- Ensure background handlers remain top-level entry points during release builds.
- Keep topic names stable and lowercase for consistency across app versions.
- Verify APNs (iOS) and FCM setup using real devices before release.

## Production readiness checklist

- Firebase and APNs are configured correctly per platform.
- Background mode/capabilities are enabled in iOS app target.
- Android notification icon/channel values are valid.
- `onTokenUpdated` pushes token to backend reliably.
- Notification payload schema (`type`, `action`, ids) is documented server-side.
- Real-device tests pass for: foreground, background-open, terminated-open, topic notifications.

## 1.0.0

- First stable production release of `push_notification_manger`.
- Includes reusable push setup, topic management, payload model, lifecycle hooks, deduplication, and Android/iOS foreground behavior controls.

## 0.1.2

- Added `showForegroundLocalNotificationOnIOS` to allow foreground local notification parity on iOS.
- Unified foreground display decision behind platform-aware helper logic.

## 0.1.1

- Added production hardening for initialization and listener lifecycle.
- Added notification lifecycle events via `onNotificationEvent`.
- Added `deduplicationWindow` support for payload duplicate filtering.
- Added `dispose()` to clean listeners and callbacks for safe reinitialization.
- Added explicit background handler callback parameter in `init`.

## 0.1.0

- Refactored push manager to be reusable and app-agnostic.
- Added `PushNotificationConfig` for dynamic setup.
- Added typed payload model: `PushNotificationPayload`.
- Unified payload handling across foreground, background-open, and terminated app launch.
- Added local notification payload parsing and tap handling.
- Added token update callback support.
- Added topic methods:
  - `subscribeToTopic`
  - `unsubscribeFromTopic`
  - `subscribeToTopics`
  - `unsubscribeFromTopics`

## 0.0.1

- Initial package scaffold.

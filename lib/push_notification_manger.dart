import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef NotificationPayloadCallback = Future<void> Function(
  PushNotificationPayload payload,
);
typedef TokenCallback = Future<void> Function(String token);
typedef BackgroundMessageHandler = Future<void> Function(RemoteMessage message);
typedef NotificationEventCallback = Future<void> Function(NotificationEvent event);

enum NotificationLifecycle {
  received,
  displayed,
  tapped,
  ignoredDuplicate,
  ignoredEmpty,
  failed,
}

class NotificationEvent {
  const NotificationEvent({
    required this.lifecycle,
    required this.source,
    this.payload,
    this.error,
  });

  final NotificationLifecycle lifecycle;
  final String source;
  final PushNotificationPayload? payload;
  final Object? error;
}

class PushNotificationConfig {
  const PushNotificationConfig({
    required this.channelId,
    required this.channelName,
    this.channelDescription,
    this.androidSmallIcon = '@mipmap/ic_launcher',
    this.handleForeground = true,
    this.showForegroundLocalNotificationOnIOS = false,
    this.processForegroundPayloadImmediately = true,
    this.requestProvisionalPermission = false,
    this.deduplicationWindow = const Duration(minutes: 2),
  });

  final String channelId;
  final String channelName;
  final String? channelDescription;
  final String androidSmallIcon;
  final bool handleForeground;
  final bool showForegroundLocalNotificationOnIOS;
  final bool processForegroundPayloadImmediately;
  final bool requestProvisionalPermission;
  final Duration deduplicationWindow;
}

class PushNotificationPayload {
  const PushNotificationPayload({
    required this.data,
    this.title,
    this.body,
    this.messageId,
    this.sentTime,
  });

  factory PushNotificationPayload.fromRemoteMessage(RemoteMessage message) {
    return PushNotificationPayload(
      data: Map<String, dynamic>.from(message.data),
      title: message.notification?.title ?? message.data['title']?.toString(),
      body: message.notification?.body ?? message.data['body']?.toString(),
      messageId: message.messageId,
      sentTime: message.sentTime,
    );
  }

  factory PushNotificationPayload.fromJsonString(String? rawPayload) {
    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return const PushNotificationPayload(data: <String, dynamic>{});
    }

    try {
      final Object? decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        return const PushNotificationPayload(data: <String, dynamic>{});
      }
      return PushNotificationPayload(
        data: Map<String, dynamic>.from(
          decoded['data'] as Map? ?? <String, dynamic>{},
        ),
        title: decoded['title']?.toString(),
        body: decoded['body']?.toString(),
        messageId: decoded['messageId']?.toString(),
      );
    } catch (_) {
      return const PushNotificationPayload(data: <String, dynamic>{});
    }
  }

  final Map<String, dynamic> data;
  final String? title;
  final String? body;
  final String? messageId;
  final DateTime? sentTime;

  String? get type => data['type']?.toString();

  String? get action => data['action']?.toString() ?? type;

  String toJsonString() {
    return jsonEncode(<String, dynamic>{
      'data': data,
      'title': title,
      'body': body,
      'messageId': messageId,
      'sentTime': sentTime?.toIso8601String(),
    });
  }
}

class PushNotificationManager {
  PushNotificationManager._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _localNotificationsInitialized = false;
  static bool _handlersRegistered = false;
  static bool _isInitializing = false;
  static bool isComingFromNotification = false;
  static String? fcmToken;

  static StreamSubscription<String>? _tokenRefreshSubscription;
  static StreamSubscription<RemoteMessage>? _onMessageSubscription;
  static StreamSubscription<RemoteMessage>? _onMessageOpenedSubscription;

  static PushNotificationConfig? _config;
  static NotificationPayloadCallback? _onPayloadReceived;
  static TokenCallback? _onTokenUpdated;
  static NotificationEventCallback? _onNotificationEvent;
  static BackgroundMessageHandler? _backgroundMessageHandler;

  static final Map<String, DateTime> _recentPayloadKeys = <String, DateTime>{};
  static const int _maxRememberedPayloads = 250;

  static Future<void> init({
    required PushNotificationConfig config,
    NotificationPayloadCallback? onPayloadReceived,
    TokenCallback? onTokenUpdated,
    BackgroundMessageHandler? onBackgroundMessage,
    NotificationEventCallback? onNotificationEvent,
  }) async {
    if (_isInitializing) {
      debugPrint('PushNotificationManager init already in progress');
      return;
    }
    _isInitializing = true;
    _config = config;
    _onPayloadReceived = onPayloadReceived;
    _onTokenUpdated = onTokenUpdated;
    _onNotificationEvent = onNotificationEvent;
    _backgroundMessageHandler = onBackgroundMessage;

    try {
      await _initializeLocalNotifications();
      await _requestNotificationPermission();
      await _refreshToken();
      _listenTokenRefresh();
      _registerMessageHandlers();
      await _checkInitialMessage();
    } finally {
      _isInitializing = false;
    }
  }

  static Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) {
      return;
    }

    final InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings(
        _config?.androidSmallIcon ?? '@mipmap/ic_launcher',
      ),
      iOS: const DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    _localNotificationsInitialized = true;
  }

  static Future<NotificationSettings> _requestNotificationPermission() async {
    final NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: _config?.requestProvisionalPermission ?? false,
      sound: true,
    );

    debugPrint('User granted permission: ${settings.authorizationStatus}');
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings;
  }

  static Future<String?> _refreshToken() async {
    final String? token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) {
      fcmToken = token;
      await _onTokenUpdated?.call(token);
      debugPrint('FCM token: $token');
    }
    return token;
  }

  static Future<void> subscribeToTopic(String topic) async {
    final String normalizedTopic = topic.trim();
    if (normalizedTopic.isEmpty) {
      debugPrint('subscribeToTopic skipped: topic is empty');
      return;
    }

    await _messaging.subscribeToTopic(normalizedTopic);
    debugPrint('Subscribed to topic: $normalizedTopic');
  }

  static Future<void> unsubscribeFromTopic(String topic) async {
    final String normalizedTopic = topic.trim();
    if (normalizedTopic.isEmpty) {
      debugPrint('unsubscribeFromTopic skipped: topic is empty');
      return;
    }

    await _messaging.unsubscribeFromTopic(normalizedTopic);
    debugPrint('Unsubscribed from topic: $normalizedTopic');
  }

  static Future<void> subscribeToTopics(Iterable<String> topics) async {
    for (final String topic in topics) {
      await subscribeToTopic(topic);
    }
  }

  static Future<void> unsubscribeFromTopics(Iterable<String> topics) async {
    for (final String topic in topics) {
      await unsubscribeFromTopic(topic);
    }
  }

  static void _listenTokenRefresh() {
    if (_tokenRefreshSubscription != null) {
      return;
    }
    _tokenRefreshSubscription =
        _messaging.onTokenRefresh.listen((String token) async {
      fcmToken = token;
      await _onTokenUpdated?.call(token);
      debugPrint('FCM token refreshed');
    });
  }

  static void _registerMessageHandlers() {
    if (_handlersRegistered) {
      return;
    }

    FirebaseMessaging.onBackgroundMessage(
      _backgroundMessageHandler ?? _firebaseMessagingBackgroundHandler,
    );

    _onMessageSubscription =
        FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final PushNotificationPayload payload =
          PushNotificationPayload.fromRemoteMessage(message);

      if (_config?.processForegroundPayloadImmediately ?? true) {
        await _handlePayload(payload, source: 'foreground');
      } else {
        await _emitEvent(
          NotificationEvent(
            lifecycle: NotificationLifecycle.received,
            source: 'foreground',
            payload: payload,
          ),
        );
      }

      if (_shouldShowForegroundLocalNotification()) {
        await _showForegroundNotification(payload);
      }
    });

    _onMessageOpenedSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      final PushNotificationPayload payload =
          PushNotificationPayload.fromRemoteMessage(message);
      await _handlePayload(payload, source: 'opened_app');
    });

    _handlersRegistered = true;
  }

  static Future<void> _checkInitialMessage() async {
    final RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage == null) {
      return;
    }

    isComingFromNotification = true;
    final PushNotificationPayload payload =
        PushNotificationPayload.fromRemoteMessage(initialMessage);
    await _handlePayload(payload, source: 'initial');
  }

  static Future<void> _showForegroundNotification(
    PushNotificationPayload payload,
  ) async {
    final PushNotificationConfig? config = _config;
    if (config == null) {
      return;
    }

    const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      interruptionLevel: InterruptionLevel.active,
    );

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      config.channelId,
      config.channelName,
      channelDescription: config.channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    final int id =
        payload.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

    try {
      await _localNotifications.show(
        id,
        payload.title ?? config.channelName,
        payload.body ?? '',
        details,
        payload: payload.toJsonString(),
      );
      await _emitEvent(
        NotificationEvent(
          lifecycle: NotificationLifecycle.displayed,
          source: 'foreground_local',
          payload: payload,
        ),
      );
    } catch (error) {
      await _emitEvent(
        NotificationEvent(
          lifecycle: NotificationLifecycle.failed,
          source: 'foreground_local',
          payload: payload,
          error: error,
        ),
      );
      rethrow;
    }
  }

  @pragma('vm:entry-point')
  static void notificationTapBackground(NotificationResponse response) {
    debugPrint(
      'Background notification tap action=${response.actionId} payload=${response.payload}',
    );
  }

  static Future<void> _onNotificationTapped(NotificationResponse response) async {
    final PushNotificationPayload payload =
        PushNotificationPayload.fromJsonString(response.payload);
    await _emitEvent(
      NotificationEvent(
        lifecycle: NotificationLifecycle.tapped,
        source: 'local_tap',
        payload: payload,
      ),
    );
    await _handlePayload(payload, source: 'local_tap');
  }

  @pragma('vm:entry-point')
  static Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message,
  ) async {
    await Firebase.initializeApp();
    final PushNotificationPayload payload =
        PushNotificationPayload.fromRemoteMessage(message);
    debugPrint('Handling background message: ${payload.messageId}');
  }

  static Future<void> _handlePayload(
    PushNotificationPayload payload, {
    required String source,
  }) async {
    _pruneDedupKeys();

    if (payload.data.isEmpty && payload.title == null && payload.body == null) {
      debugPrint('Ignored empty notification payload from $source');
      await _emitEvent(
        NotificationEvent(
          lifecycle: NotificationLifecycle.ignoredEmpty,
          source: source,
          payload: payload,
        ),
      );
      return;
    }

    final String payloadKey = _payloadKey(payload);
    if (_recentPayloadKeys.containsKey(payloadKey)) {
      debugPrint('Ignored duplicate notification payload from $source');
      await _emitEvent(
        NotificationEvent(
          lifecycle: NotificationLifecycle.ignoredDuplicate,
          source: source,
          payload: payload,
        ),
      );
      return;
    }
    if (_recentPayloadKeys.length >= _maxRememberedPayloads) {
      _recentPayloadKeys.remove(_recentPayloadKeys.keys.first);
    }
    _recentPayloadKeys[payloadKey] = DateTime.now();

    debugPrint(
      'Notification from $source, action=${payload.action}, data=${payload.data}',
    );
    await _emitEvent(
      NotificationEvent(
        lifecycle: NotificationLifecycle.received,
        source: source,
        payload: payload,
      ),
    );
    try {
      await _onPayloadReceived?.call(payload);
    } catch (error) {
      await _emitEvent(
        NotificationEvent(
          lifecycle: NotificationLifecycle.failed,
          source: source,
          payload: payload,
          error: error,
        ),
      );
      rethrow;
    }
  }

  static String _payloadKey(PushNotificationPayload payload) {
    if (payload.messageId != null && payload.messageId!.isNotEmpty) {
      return payload.messageId!;
    }
    return jsonEncode(<String, dynamic>{
      'title': payload.title,
      'body': payload.body,
      'data': payload.data,
    });
  }

  static bool _shouldShowForegroundLocalNotification() {
    final PushNotificationConfig? config = _config;
    if (config == null || !config.handleForeground) {
      return false;
    }
    if (Platform.isAndroid) {
      return true;
    }
    if (Platform.isIOS) {
      return config.showForegroundLocalNotificationOnIOS;
    }
    return false;
  }

  static void _pruneDedupKeys() {
    final Duration window =
        _config?.deduplicationWindow ?? const Duration(minutes: 2);
    final DateTime now = DateTime.now();
    final List<String> keysToRemove = <String>[];
    _recentPayloadKeys.forEach((String key, DateTime timestamp) {
      if (now.difference(timestamp) > window) {
        keysToRemove.add(key);
      }
    });
    for (final String key in keysToRemove) {
      _recentPayloadKeys.remove(key);
    }
  }

  static Future<void> _emitEvent(NotificationEvent event) async {
    try {
      await _onNotificationEvent?.call(event);
    } catch (_) {
      // Keep notification pipeline stable even if observer callback fails.
    }
  }

  static Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _onMessageSubscription?.cancel();
    await _onMessageOpenedSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _onMessageSubscription = null;
    _onMessageOpenedSubscription = null;
    _handlersRegistered = false;
    _onPayloadReceived = null;
    _onTokenUpdated = null;
    _onNotificationEvent = null;
    _backgroundMessageHandler = null;
    _recentPayloadKeys.clear();
  }

  @visibleForTesting
  static Future<void> debugHandlePayloadForTest(
    PushNotificationPayload payload, {
    String source = 'test',
  }) {
    return _handlePayload(payload, source: source);
  }

  @visibleForTesting
  static Future<void> debugSetObserversForTest({
    NotificationPayloadCallback? onPayloadReceived,
    NotificationEventCallback? onNotificationEvent,
  }) async {
    _onPayloadReceived = onPayloadReceived;
    _onNotificationEvent = onNotificationEvent;
  }

  @visibleForTesting
  static Future<void> debugSetTokenSubscriptionForTest(
    StreamSubscription<String>? subscription,
  ) async {
    _tokenRefreshSubscription = subscription;
  }

  @visibleForTesting
  static int get debugRecentPayloadCount => _recentPayloadKeys.length;

  @visibleForTesting
  static bool get debugHandlersRegistered => _handlersRegistered;

  @visibleForTesting
  static bool get debugHasPayloadObserver => _onPayloadReceived != null;

  @visibleForTesting
  static bool get debugHasEventObserver => _onNotificationEvent != null;
}
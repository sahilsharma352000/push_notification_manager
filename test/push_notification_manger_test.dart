import 'package:flutter_test/flutter_test.dart';
import 'package:push_notification_manger/push_notification_manger.dart';

void main() {
  group('PushNotificationPayload JSON parsing', () {
    test('returns empty payload for null/empty input', () {
      final PushNotificationPayload fromNull =
          PushNotificationPayload.fromJsonString(null);
      final PushNotificationPayload fromEmpty =
          PushNotificationPayload.fromJsonString('');

      expect(fromNull.data, isEmpty);
      expect(fromEmpty.data, isEmpty);
      expect(fromNull.title, isNull);
      expect(fromEmpty.body, isNull);
    });

    test('parses expected fields from valid JSON payload', () {
      const String rawPayload =
          '{"data":{"type":"chat","chatId":"123"},"title":"Hi","body":"New message","messageId":"m1"}';

      final PushNotificationPayload payload =
          PushNotificationPayload.fromJsonString(rawPayload);

      expect(payload.type, 'chat');
      expect(payload.action, 'chat');
      expect(payload.data['chatId'], '123');
      expect(payload.title, 'Hi');
      expect(payload.body, 'New message');
      expect(payload.messageId, 'm1');
    });

    test('returns empty payload for malformed JSON', () {
      const String malformed = '{"data":{"type":"chat"';

      final PushNotificationPayload payload =
          PushNotificationPayload.fromJsonString(malformed);

      expect(payload.data, isEmpty);
      expect(payload.title, isNull);
    });

    test('toJsonString keeps payload fields', () {
      final PushNotificationPayload payload = PushNotificationPayload(
        data: const <String, dynamic>{'type': 'order', 'orderId': '42'},
        title: 'Order update',
        body: 'Your order is shipped',
        messageId: 'order-1',
      );

      final PushNotificationPayload parsed =
          PushNotificationPayload.fromJsonString(payload.toJsonString());

      expect(parsed.type, 'order');
      expect(parsed.data['orderId'], '42');
      expect(parsed.title, 'Order update');
      expect(parsed.body, 'Your order is shipped');
      expect(parsed.messageId, 'order-1');
    });
  });

  group('PushNotificationConfig defaults', () {
    test('uses safe defaults', () {
      const PushNotificationConfig config = PushNotificationConfig(
        channelId: 'general',
        channelName: 'General',
      );

      expect(config.androidSmallIcon, '@mipmap/ic_launcher');
      expect(config.handleForeground, isTrue);
      expect(config.showForegroundLocalNotificationOnIOS, isFalse);
      expect(config.processForegroundPayloadImmediately, isTrue);
      expect(config.requestProvisionalPermission, isFalse);
      expect(config.deduplicationWindow, const Duration(minutes: 2));
    });
  });
}

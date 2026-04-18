import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:push_notification_manger/push_notification_manger.dart';

void main() {
  setUp(() async {
    await PushNotificationManager.dispose();
  });

  group('PushNotificationManager lifecycle', () {
    test('deduplicates repeated payloads', () async {
      int handledCount = 0;
      await PushNotificationManager.debugSetObserversForTest(
        onPayloadReceived: (PushNotificationPayload payload) async {
          handledCount++;
        },
      );

      const PushNotificationPayload payload = PushNotificationPayload(
        data: <String, dynamic>{'type': 'chat', 'chatId': 'c1'},
        messageId: 'msg-1',
      );

      await PushNotificationManager.debugHandlePayloadForTest(payload);
      await PushNotificationManager.debugHandlePayloadForTest(payload);

      expect(handledCount, 1);
      expect(PushNotificationManager.debugRecentPayloadCount, 1);
    });

    test('dispose clears observers and dedup cache', () async {
      int eventCount = 0;
      await PushNotificationManager.debugSetObserversForTest(
        onPayloadReceived: (PushNotificationPayload payload) async {},
        onNotificationEvent: (NotificationEvent event) async {
          eventCount++;
        },
      );

      await PushNotificationManager.debugHandlePayloadForTest(
        const PushNotificationPayload(
          data: <String, dynamic>{'type': 'promo'},
          messageId: 'promo-1',
        ),
      );

      expect(PushNotificationManager.debugRecentPayloadCount, 1);
      expect(PushNotificationManager.debugHasPayloadObserver, isTrue);
      expect(PushNotificationManager.debugHasEventObserver, isTrue);
      expect(eventCount, greaterThanOrEqualTo(1));

      await PushNotificationManager.dispose();

      expect(PushNotificationManager.debugRecentPayloadCount, 0);
      expect(PushNotificationManager.debugHasPayloadObserver, isFalse);
      expect(PushNotificationManager.debugHasEventObserver, isFalse);
      expect(PushNotificationManager.debugHandlersRegistered, isFalse);
    });

    test('dispose safely handles active token refresh subscription', () async {
      final StreamController<String> controller = StreamController<String>();
      final StreamSubscription<String> subscription =
          controller.stream.listen((_) {});

      await PushNotificationManager.debugSetTokenSubscriptionForTest(
        subscription,
      );
      await expectLater(PushNotificationManager.dispose(), completes);
      await controller.close();
    });
  });
}

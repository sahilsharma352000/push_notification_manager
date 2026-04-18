import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:push_notification_manger/push_notification_manger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const PushNotificationExampleApp());
}

class PushNotificationExampleApp extends StatelessWidget {
  const PushNotificationExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PushHomePage(),
    );
  }
}

class PushHomePage extends StatefulWidget {
  const PushHomePage({super.key});

  @override
  State<PushHomePage> createState() => _PushHomePageState();
}

class _PushHomePageState extends State<PushHomePage> {
  String _token = 'Not fetched yet';
  String _lastEvent = 'No notification received yet';

  @override
  void initState() {
    super.initState();
    _setupPush();
  }

  Future<void> _setupPush() async {
    await PushNotificationManager.init(
      config: const PushNotificationConfig(
        channelId: 'general_notifications',
        channelName: 'General Notifications',
        channelDescription: 'General app updates and alerts',
      ),
      onTokenUpdated: (String token) async {
        if (!mounted) return;
        setState(() => _token = token);
      },
      onPayloadReceived: (PushNotificationPayload payload) async {
        final String route = _mapPayloadToRoute(payload);
        if (!mounted) return;
        setState(() {
          _lastEvent =
              'type=${payload.type}, action=${payload.action}, route=$route, data=${payload.data}';
        });
      },
    );
  }

  String _mapPayloadToRoute(PushNotificationPayload payload) {
    switch (payload.type) {
      case 'chat':
        return '/chat';
      case 'order':
        return '/order-details';
      case 'promo':
        return '/offers';
      default:
        return '/home';
    }
  }

  Future<void> _subscribeDefaults() async {
    await PushNotificationManager.subscribeToTopics(
      <String>['chat', 'order', 'promo'],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Subscribed to chat, order, promo')),
    );
  }

  Future<void> _unsubscribeDefaults() async {
    await PushNotificationManager.unsubscribeFromTopics(
      <String>['chat', 'order', 'promo'],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unsubscribed from chat, order, promo')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Push Notification Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'FCM Token',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SelectableText(_token),
            const SizedBox(height: 24),
            const Text(
              'Last Notification Event',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_lastEvent),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                ElevatedButton(
                  onPressed: _subscribeDefaults,
                  child: const Text('Subscribe default topics'),
                ),
                ElevatedButton(
                  onPressed: _unsubscribeDefaults,
                  child: const Text('Unsubscribe default topics'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Payload route mapping: chat -> /chat, order -> /order-details, promo -> /offers',
            ),
          ],
        ),
      ),
    );
  }
}

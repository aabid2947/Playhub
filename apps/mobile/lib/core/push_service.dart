import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/router.dart';
import 'package:playhub/features/notifications/data/notification_providers.dart';

/// Owns Firebase init, FCM token registration, and the foreground +
/// background + tap-to-route handlers.
///
/// Initialization is platform-aware: on Android/iOS we rely on the platform
/// config files (google-services.json / GoogleService-Info.plist) so we
/// don't need a generated firebase_options.dart for v0.8. On web we
/// skip — that platform isn't a Sprint-4 target.
class PushService {
  PushService(this._ref);
  final Ref _ref;

  static final _localNotifs = FlutterLocalNotificationsPlugin();
  static const _androidChannel = AndroidNotificationChannel(
    'playhub_default',
    'PlayHub notifications',
    description: 'Announcements, messages, and reminders',
    importance: Importance.high,
  );

  bool _initialised = false;

  Future<void> ensureInitialised() async {
    if (_initialised) return;
    if (kIsWeb) {
      _initialised = true;
      return;
    }

    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[push] Firebase.initializeApp failed: $e');
      _initialised = true;
      return;
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    // Foreground display via flutter_local_notifications (FCM doesn't
    // surface the system notification while the app is open).
    await _localNotifs.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (resp) {
        final link = resp.payload;
        if (link != null && link.isNotEmpty) _route(link);
      },
    );
    if (Platform.isAndroid) {
      await _localNotifs
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }

    // Initial token + listen for refreshes.
    final token = await messaging.getToken();
    if (token != null) await _register(token);
    messaging.onTokenRefresh.listen(_register);

    // Foreground messages → show as a local notification.
    FirebaseMessaging.onMessage.listen((m) async {
      final title = m.notification?.title
          ?? (m.data['title'] as String?) ?? 'PlayHub';
      final body = m.notification?.body
          ?? (m.data['body'] as String?) ?? '';
      final deepLink = m.data['deep_link'] as String?;
      await _localNotifs.show(
        m.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id, _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high, priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: deepLink,
      );
    });

    // Background → tap routes via deep_link.
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      final link = m.data['deep_link'] as String?;
      if (link != null && link.isNotEmpty) _route(link);
    });

    // Cold-start: launched from a tap on a notification.
    final initial = await messaging.getInitialMessage();
    final coldLink = initial?.data['deep_link'] as String?;
    if (coldLink != null && coldLink.isNotEmpty) {
      // Defer a frame so the router is mounted.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _route(coldLink));
    }

    _initialised = true;
  }

  Future<void> _register(String token) async {
    final repo = _ref.read(notificationsRepoProvider);
    final platform = kIsWeb
        ? 'web'
        : Platform.isAndroid
            ? 'android'
            : Platform.isIOS
                ? 'ios'
                : 'web';
    try {
      await repo.registerDeviceToken(token: token, platform: platform);
    } catch (e) {
      debugPrint('[push] register_device_token failed: $e');
    }
  }

  void _route(String deepLink) {
    try {
      final router = _ref.read(routerProvider);
      router.push(deepLink);
    } catch (e) {
      debugPrint('[push] route failed: $e');
    }
  }
}

final pushServiceProvider =
    Provider<PushService>((ref) => PushService(ref));

/// Side-effect provider — watch this from the app shell to start the push
/// pipeline once the user is signed in.
final pushBootstrapProvider = FutureProvider<void>((ref) async {
  await ref.watch(pushServiceProvider).ensureInitialised();
});

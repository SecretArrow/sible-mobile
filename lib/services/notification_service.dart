/// Notification service - wraps flutter_local_notifications.
/// Safe to initialize in both the main isolate and the background isolate.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/constants.dart';
import '../core/theme.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    try {
      await _plugin.initialize(initSettings);
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannelGroup(
        const AndroidNotificationChannelGroup('sible_group', 'Sible Miner'),
      );
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        Channels.service,
        'Background service',
        description: 'Keeps the Sible Miner worker alive',
        groupId: 'sible_group',
        importance: Importance.low,
        playSound: false,
        showBadge: false,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        Channels.events,
        'Cycle summaries',
        description: 'Mining / acceleration / claim results',
        groupId: 'sible_group',
        importance: Importance.defaultImportance,
      ));
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        Channels.alerts,
        'Alerts',
        description: 'Login failures, bans, proxy exhaustion',
        groupId: 'sible_group',
        importance: Importance.high,
      ));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    } catch (_) {
      // Permission is optional - a plugin hiccup must never crash startup.
      return false;
    }
  }

  Future<void> notify({
    required String title,
    required String body,
    String channel = Channels.events,
    bool silent = false,
  }) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel,
            _channelName(channel),
            channelDescription: 'Sible Miner notifications',
            importance: channel == Channels.alerts
                ? Importance.high
                : Importance.defaultImportance,
            priority: channel == Channels.alerts
                ? Priority.high
                : Priority.defaultPriority,
            playSound: !silent,
            color: channel == Channels.alerts
                ? SibleTheme.danger
                : SibleTheme.primary,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> notifyAlert({required String title, required String body}) =>
      notify(title: title, body: body, channel: Channels.alerts);

  String _channelName(String id) {
    switch (id) {
      case Channels.service:
        return 'Background service';
      case Channels.alerts:
        return 'Alerts';
      default:
        return 'Cycle summaries';
    }
  }
}

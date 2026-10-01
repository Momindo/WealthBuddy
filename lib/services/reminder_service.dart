// Schedules payday reminders as local notifications. Everything happens on the phone:
// messages are written by domain/reminders.dart and handed to the OS scheduler. No server, no push service.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/format.dart';
import '../domain/models.dart';
import '../domain/reminders.dart';

class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _android = AndroidNotificationDetails(
    'payday',
    'Payday reminders',
    channelDescription: 'A reminder on payday to put money aside for your projects',
    importance: Importance.defaultImportance,
    icon: 'ic_stat_wb',
  );

  Future<void> _init() async {
    if (_ready) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_wb'),
      iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
    );
    await _plugin.initialize(settings: settings);
    _ready = true;
  }

  /// Asks the OS for permission to show notifications. Returns false if refused or unavailable.
  Future<bool> requestPermission() async {
    try {
      await _init();
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
    } catch (_) {}
    return false;
  }

  /// Replaces all scheduled reminders with the next three paydays' messages.
  /// Called whenever the data changes and when the app opens, so the messages always match the plan.
  Future<void> reschedule(AppData d) async {
    try {
      await _init();
      await _plugin.cancelAll();
      if (!d.settings.reminders) return;
      final now = DateTime.now();
      final list = paydayReminders(d, today: todayIso(), count: 3);
      for (var i = 0; i < list.length; i++) {
        final r = list[i];
        final when = DateTime(int.parse(r.date.substring(0, 4)), int.parse(r.date.substring(5, 7)), int.parse(r.date.substring(8, 10)), 15);
        if (!when.isAfter(now)) continue;
        await _plugin.zonedSchedule(
          id: i + 1,
          scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC), // 3 pm on the phone's clock, as an exact instant
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(_android.channelId, _android.channelName,
                channelDescription: _android.channelDescription, icon: _android.icon, styleInformation: BigTextStyleInformation(r.body)),
            iOS: const DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: r.title,
          body: r.body,
        );
      }
    } catch (_) {
      // Reminders must never break the app (no permission, tests, unsupported platform).
    }
  }
}

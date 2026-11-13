/// Shows the "focus done" and "break over" notifications, scheduled on the device.
///
/// Notifications are local: the phone's own alarm system shows them. Nothing goes through a
/// server, and no push token or ID is ever created.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/phase_alerts.dart';

/// Whether alerts can be shown, and whether they will arrive on time.
enum AlertAccess {
  /// Notifications are allowed and will arrive on time.
  ready,

  /// Notifications are allowed, but Android's "Alarms & reminders" access is off, so they may
  /// arrive late while the phone is idle.
  mayBeLate,

  /// Notifications are turned off for the app.
  blocked,
}

/// Schedules and cancels phase alerts.
abstract interface class PhaseNotifier {
  /// Prepares the notification system. Call once at startup.
  Future<void> initialize();

  /// Asks for permission to show notifications (the system asks at most once).
  Future<AlertAccess> requestAccess();

  /// The current access, without asking.
  Future<AlertAccess> checkAccess();

  /// Opens the Android setting that allows on-time alerts ("Alarms & reminders").
  Future<void> openExactAlarmSettings();

  /// Replaces every alert still waiting to be shown with [alerts]. Alerts that are not at least
  /// [PhaseAlertPlanner.minimumLead] after [now] are skipped (the system can't schedule the past).
  Future<void> schedule(List<PhaseAlert> alerts, {required DateTime now});

  /// Cancels the alerts still waiting to be shown. Alerts already on screen stay.
  Future<void> cancelPending();
}

/// [PhaseNotifier] using flutter_local_notifications.
class LocalPhaseNotifier implements PhaseNotifier {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const String _channelId = 'phase_changes';

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Focus and break alerts',
      channelDescription: 'Tells you when a focus block or a break ends.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
    ),
  );

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        // Permission is asked for when the user first starts a timer, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  @override
  Future<AlertAccess> requestAccess() async {
    try {
      if (_isAndroid) {
        await _android?.requestNotificationsPermission();
      } else {
        await _ios?.requestPermissions(alert: true, sound: true);
      }
    } on PlatformException catch (error) {
      // For example "a permission request is already in progress". The answer is read below.
      debugPrint('Notification permission request failed: ${error.message}');
    }
    return checkAccess();
  }

  @override
  Future<AlertAccess> checkAccess() async {
    if (_isAndroid) {
      final android = _android;
      if (android == null) {
        return AlertAccess.blocked;
      }
      if (await android.areNotificationsEnabled() != true) {
        return AlertAccess.blocked;
      }
      final exact = await android.canScheduleExactNotifications() ?? false;
      return exact ? AlertAccess.ready : AlertAccess.mayBeLate;
    }
    final options = await _ios?.checkPermissions();
    return options?.isEnabled == true ? AlertAccess.ready : AlertAccess.blocked;
  }

  @override
  Future<void> openExactAlarmSettings() async {
    await _android?.requestExactAlarmsPermission();
  }

  @override
  Future<void> schedule(List<PhaseAlert> alerts, {required DateTime now}) async {
    await _plugin.cancelAllPendingNotifications();
    final mode = await _scheduleMode();
    final earliest = now.add(PhaseAlertPlanner.minimumLead);
    for (final (index, alert) in alerts.indexed) {
      if (alert.at.isBefore(earliest)) {
        continue;
      }
      try {
        await _plugin.zonedSchedule(
          id: index + 1,
          scheduledDate: tz.TZDateTime.from(alert.at, tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: mode,
          title: alert.title,
          body: alert.body,
        );
      } on Object catch (error) {
        // One alert failing must not stop the others from being scheduled.
        debugPrint('Scheduling an alert failed: $error');
      }
    }
  }

  @override
  Future<void> cancelPending() => _plugin.cancelAllPendingNotifications();

  Future<AndroidScheduleMode> _scheduleMode() async {
    if (!_isAndroid) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    return exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }
}

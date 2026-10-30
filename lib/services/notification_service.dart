import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance =
      NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings =
        InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);

    // Request notification permission (Android 13+)
    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> scheduleTaskReminder({
    required int id,
    required String title,
    required DateTime dueDate,
  }) async {
    await init();

    // Schedule 1 hour before due date (or immediately if past)
    var scheduled = dueDate.subtract(const Duration(hours: 1));
    if (scheduled.isBefore(DateTime.now())) {
      scheduled = DateTime.now().add(const Duration(seconds: 5));
    }

    const androidDetails = AndroidNotificationDetails(
      'todo_channel',
      'Task Reminders',
      channelDescription: 'Reminders for your to-do tasks',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    await _plugin.zonedSchedule(
      id,
      '📝 Task Reminder',
      title,
      tz.TZDateTime.from(scheduled, tz.local),
      const NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelReminder(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> showTestNotification() async {
    await init();
    await _plugin.show(
      0,
      '🔔 Notifications active!',
      'You will be reminded about tasks with due dates.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'todo_channel',
          'Task Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
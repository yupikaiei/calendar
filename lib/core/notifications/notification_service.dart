import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:logging/logging.dart';
import '../db/database.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  final _logger = Logger('NotificationService');
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: true,
          requestAlertPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onSelectNotification,
    );

    // Request Android 13+ permissions
    final androidImplementation = _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
    }

    _initialized = true;
    _logger.info('NotificationService initialized successfully.');
  }

  void _onSelectNotification(NotificationResponse details) {
    _logger.info('Notification tapped: ${details.payload}');
    // We could parse the payload into an event ID and navigate there if needed
  }

  Future<void> scheduleEventReminder(Event event, int minutesBefore) async {
    if (!_initialized) await init();

    final scheduledDate = event.startDate.subtract(
      Duration(minutes: minutesBefore),
    );
    if (scheduledDate.isBefore(DateTime.now())) {
      _logger.info('Reminder for ${event.title} is in the past, skipping.');
      return;
    }

    final androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'frelsi_cal_reminders',
      'Event Reminders',
      channelDescription: 'Notifications for upcoming calendar events',
      importance: Importance.max,
      priority: Priority.high,
    );
    final iOSPlatformChannelSpecifics = const DarwinNotificationDetails();
    final platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    final notificationId = '${event.id}_$minutesBefore'.hashCode;
    String body = _formatReminderBody(event, minutesBefore);

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id: notificationId,
      title: event.title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: event.id.toString(),
    );

    _logger.info(
      'Scheduled reminder for event ${event.title} at $scheduledDate (ID: $notificationId)',
    );
  }

  String _formatReminderBody(Event event, int minutesBefore) {
    if (minutesBefore == 0) return 'Starts now!';
    final duration = Duration(minutes: minutesBefore);
    if (duration.inDays > 0) return 'Starts in ${duration.inDays} day(s)';
    if (duration.inHours > 0) return 'Starts in ${duration.inHours} hour(s)';
    return 'Starts in $minutesBefore minutes';
  }

  Future<void> cancelEventReminders(
    int eventId,
    List<int> reminderMinutes,
  ) async {
    if (!_initialized) return;

    for (final mins in reminderMinutes) {
      final notificationId = '${eventId}_$mins'.hashCode;
      await _flutterLocalNotificationsPlugin.cancel(id: notificationId);
      _logger.info('Cancelled reminder ID $notificationId for event $eventId');
    }
  }

  Future<void> cancelAllReminders() async {
    if (!_initialized) return;
    await _flutterLocalNotificationsPlugin.cancelAll();
  }
}

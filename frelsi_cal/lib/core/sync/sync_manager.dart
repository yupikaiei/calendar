import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/caldav_service.dart';
import '../db/database.dart';
import '../providers/providers.dart';
import 'ical_parser.dart';

final syncManagerProvider = Provider<SyncManager>((ref) {
  final manager = SyncManager(ref.read(databaseProvider));
  return manager;
});

class SyncManager with WidgetsBindingObserver {
  final AppDatabase _db;
  final _logger = Logger('SyncManager');

  SyncManager(this._db) {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _logger.info('App resumed. Triggering sync with Radicale...');
      performSync();
    }
  }

  Future<CalDavService?> _getCalDavService() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl =
        prefs.getString('server_url') ?? 'http://192.168.2.35:5232';
    final username = prefs.getString('username') ?? 'user';
    final password = prefs.getString('password') ?? 'password';

    if (serverUrl.isEmpty || username.isEmpty) {
      return null;
    }

    return CalDavService(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
  }

  Future<void> performSync() async {
    final calDavService = await _getCalDavService();
    if (calDavService == null) {
      _logger.warning('Missing CalDAV settings, skipping sync.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? 'user';
    final userPath = '/$username/';

    _logger.info('Discovering calendars for user $username...');
    final calendars = await calDavService.getCalendars(userPath);

    if (calendars.isEmpty) {
      _logger.info(
        'No calendars found. Automatically creating /frelsi/ calendar...',
      );
      final created = await calDavService.createCalendar(
        '/$username/frelsi/',
        'Frelsi Calendar',
      );
      if (created) {
        calendars.addAll(await calDavService.getCalendars(userPath));
      }
    }

    // Upsert discovered calendars into DB
    for (final calMap in calendars) {
      final urlPath = calMap['urlPath']!;
      final displayName = calMap['displayName']!;
      final color = calMap['color']!;

      final existingCalQuery = await (_db.select(
        _db.calendars,
      )..where((c) => c.urlPath.equals(urlPath))).get();
      if (existingCalQuery.isEmpty) {
        await _db.insertCalendar(
          CalendarsCompanion.insert(
            urlPath: urlPath,
            displayName: displayName,
            color: Value(color),
          ),
        );
      } else {
        final existing = existingCalQuery.first;
        await _db.updateCalendar(
          existing
              .copyWith(displayName: displayName, color: Value(color))
              .toCompanion(true),
        );
      }
    }

    // Process sync for each tracked calendar
    final allDbCalendars = await _db.getCalendars();
    for (final dbCal in allDbCalendars) {
      final calendarPath = dbCal.urlPath;
      var cTag = await calDavService.getCTag(calendarPath);
      if (cTag == null) continue;

      _logger.info('Syncing calendar ${dbCal.displayName} ($calendarPath)...');

      // 1. PUSH local events associated with this calendar
      // For backwards compatibility before multiple calendars, also push events where calendarId is null to this first available cal
      final localEvents =
          await (_db.select(_db.events)..where(
                (e) => e.calendarId.equals(dbCal.id) | e.calendarId.isNull(),
              ))
              .get();
      int pushCount = 0;
      for (final event in localEvents) {
        final icsData = ICalParser.generateIcs(event);
        final success = await calDavService.putEvent(
          calendarPath,
          '${event.uid}.ics',
          icsData,
        );
        if (success) {
          pushCount++;
          // If it was null, tie it securely to this calendar now
          if (event.calendarId == null) {
            await _db.updateEvent(
              event.copyWith(calendarId: Value(dbCal.id)).toCompanion(true),
            );
          }
        }
      }
      if (pushCount > 0)
        _logger.info('Pushed $pushCount events to ${dbCal.displayName}.');

      // 2. DELETE local deleted events
      final deletedUids = await _db.getDeletedEventUids();
      int pushDeletedCount = 0;
      for (final uid in deletedUids) {
        // Notice: we iterate deletes across all to brute-force since we lack history of which dir it lived in.
        final success = await calDavService.deleteEvent(
          calendarPath,
          '$uid.ics',
        );
        if (success) {
          await _db.removeDeletedEventUid(uid);
          pushDeletedCount++;
        }
      }
      if (pushDeletedCount > 0)
        _logger.info(
          'Synced $pushDeletedCount deletions to ${dbCal.displayName}.',
        );

      // 3. PULL server events if cTag changed
      cTag = await calDavService.getCTag(
        calendarPath,
      ); // Refresh cTag after push
      if (cTag != null && cTag != dbCal.cTag) {
        _logger.info(
          'CTag changed for ${dbCal.displayName}. Fetching server events...',
        );
        final eventsIcs = await calDavService.getCalendarEvents(calendarPath);

        int pullCount = 0;
        for (final icsString in eventsIcs) {
          final companion = ICalParser.parseEvent(icsString);
          if (companion != null) {
            final serverUid = companion.uid.value;
            final existingQuery = await (_db.select(
              _db.events,
            )..where((e) => e.uid.equals(serverUid))).get();

            if (existingQuery.isNotEmpty) {
              final existingEvent = existingQuery.first;
              await _db.updateEvent(
                companion.copyWith(
                  id: Value(existingEvent.id),
                  calendarId: Value(dbCal.id),
                ),
              );
            } else {
              await _db.insertEvent(
                companion.copyWith(calendarId: Value(dbCal.id)),
              );
            }
            pullCount++;
          }
        }
        _logger.info('Pulled $pullCount events for ${dbCal.displayName}.');

        // Update stored cTag
        await _db.updateCalendar(
          dbCal.copyWith(cTag: Value(cTag)).toCompanion(true),
        );
      } else {
        _logger.info('${dbCal.displayName} is up to date.');
      }
    }
  }
}

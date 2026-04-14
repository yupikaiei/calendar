import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frelsi_cal/core/db/database.dart';
import 'package:frelsi_cal/core/network/caldav_service.dart';
import 'package:frelsi_cal/core/sync/sync_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake CalDavService that records calls and returns canned data.
class FakeCalDavService extends Fake implements CalDavService {
  String? cTag;
  List<Map<String, String>> calendarsToReturn = [];
  List<String> icsStringsToReturn = [];
  bool putEventResult = true;
  bool createCalendarResult = true;
  bool deleteEventResult = true;

  // Track calls
  final List<String> putEventCalls = [];
  final List<String> deleteEventCalls = [];
  bool createCalendarCalled = false;
  String? createCalendarPath;
  bool closeCalled = false;

  @override
  Future<String?> getCTag(String calendarPath) async => cTag;

  @override
  Future<List<Map<String, String>>> getCalendars(String userPath) async =>
      calendarsToReturn;

  @override
  Future<List<String>> getCalendarEvents(String calendarPath) async =>
      icsStringsToReturn;

  @override
  Future<bool> putEvent(
      String calendarPath, String filename, String icsData) async {
    putEventCalls.add(filename);
    return putEventResult;
  }

  @override
  Future<bool> createCalendar(String calendarPath, String displayName) async {
    createCalendarCalled = true;
    createCalendarPath = calendarPath;
    return createCalendarResult;
  }

  @override
  Future<bool> deleteEvent(String calendarPath, String filename) async {
    deleteEventCalls.add(filename);
    return deleteEventResult;
  }

  @override
  void close() {
    closeCalled = true;
  }
}

AppDatabase _createTestDb() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}

void main() {
  late AppDatabase db;
  late FakeCalDavService fakeService;

  setUp(() {
    db = _createTestDb();
    fakeService = FakeCalDavService();
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://cal.example.com',
      'username': 'testuser',
    });
  });

  tearDown(() async {
    await db.close();
  });

  group('performSync', () {
    test('skips sync when calDavServiceFactory returns null', () async {
      final manager = SyncManager.forTesting(
        db,
        calDavServiceFactory: () async => null,
      );

      // Should complete without error
      await manager.performSync();
    });

    test('creates calendar when none exist on server', () async {
      fakeService.calendarsToReturn = [];
      fakeService.createCalendarResult = true;

      // After createCalendar, getCalendars returns the new calendar
      final manager = SyncManager.forTesting(
        db,
        calDavServiceFactory: () async {
          return fakeService;
        },
      );

      // Replace getCalendars to simulate: first call empty, second call with data
      // We need a more sophisticated fake for this. Just verify createCalendar is called.
      fakeService.calendarsToReturn = [];
      await manager.performSync();

      expect(fakeService.createCalendarCalled, isTrue);
      expect(fakeService.createCalendarPath, '/testuser/frelsi/');
      expect(fakeService.closeCalled, isTrue);
    });

    test('upserts discovered calendars into database', () async {
      fakeService.calendarsToReturn = [
        {
          'urlPath': '/testuser/work/',
          'displayName': 'Work',
          'color': '#FF0000',
        },
        {
          'urlPath': '/testuser/personal/',
          'displayName': 'Personal',
          'color': '#00FF00',
        },
      ];

      final manager = SyncManager.forTesting(
        db,
        calDavServiceFactory: () async => fakeService,
      );
      await manager.performSync();

      final cals = await db.getCalendars();
      expect(cals.length, 2);
      expect(cals.map((c) => c.displayName).toList()..sort(),
          ['Personal', 'Work']);
    });

    test('pushes local events to server', () async {
      // Insert a calendar and an event into DB
      final calId = await db.insertCalendar(CalendarsCompanion.insert(
        urlPath: '/testuser/work/',
        displayName: 'Work',
      ));

      await db.insertEvent(EventsCompanion.insert(
        uid: 'local-event-1',
        title: 'Meeting',
        startDate: DateTime(2024, 3, 15, 10),
        endDate: DateTime(2024, 3, 15, 11),
        calendarId: Value(calId),
      ));

      fakeService.calendarsToReturn = [
        {
          'urlPath': '/testuser/work/',
          'displayName': 'Work',
          'color': '#FF0000',
        },
      ];
      fakeService.putEventResult = true;
      fakeService.cTag = 'ctag-1';

      final manager = SyncManager.forTesting(
        db,
        calDavServiceFactory: () async => fakeService,
      );
      await manager.performSync();

      expect(fakeService.putEventCalls, contains('local-event-1.ics'));
    });

    test('pushes deletions to server and cleans up', () async {
      await db.insertCalendar(CalendarsCompanion.insert(
        urlPath: '/testuser/work/',
        displayName: 'Work',
      ));

      await db.markEventDeleted('deleted-uid-1');

      fakeService.calendarsToReturn = [
        {
          'urlPath': '/testuser/work/',
          'displayName': 'Work',
          'color': '#FF0000',
        },
      ];
      fakeService.deleteEventResult = true;
      fakeService.cTag = 'ctag-1';

      final manager = SyncManager.forTesting(
        db,
        calDavServiceFactory: () async => fakeService,
      );
      await manager.performSync();

      expect(fakeService.deleteEventCalls, contains('deleted-uid-1.ics'));
      // After successful delete, uid should be removed from deleted list
      final remaining = await db.getDeletedEventUids();
      expect(remaining, isEmpty);
    });

    test('pulls server events when cTag changes', () async {
      await db.insertCalendar(CalendarsCompanion.insert(
        urlPath: '/testuser/work/',
        displayName: 'Work',
        cTag: const Value('old-ctag'),
      ));

      fakeService.calendarsToReturn = [
        {
          'urlPath': '/testuser/work/',
          'displayName': 'Work',
          'color': '#FF0000',
        },
      ];
      fakeService.cTag = 'new-ctag';
      fakeService.icsStringsToReturn = [
        '''BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VEVENT\r\nUID:server-event-1\r\nSUMMARY:Server Meeting\r\nDTSTART:20240315T100000Z\r\nDTEND:20240315T110000Z\r\nDTSTAMP:20240315T080000Z\r\nEND:VEVENT\r\nEND:VCALENDAR''',
      ];

      final manager = SyncManager.forTesting(
        db,
        calDavServiceFactory: () async => fakeService,
      );
      await manager.performSync();

      // Event should be in DB
      final events = await db.getEvents();
      expect(events.any((e) => e.uid == 'server-event-1'), isTrue);

      // cTag should be updated
      final cals = await db.getCalendars();
      final workCal = cals.firstWhere((c) => c.urlPath == '/testuser/work/');
      expect(workCal.cTag, 'new-ctag');
    });

    test('skips pull when cTag unchanged', () async {
      await db.insertCalendar(CalendarsCompanion.insert(
        urlPath: '/testuser/work/',
        displayName: 'Work',
        cTag: const Value('same-ctag'),
      ));

      fakeService.calendarsToReturn = [
        {
          'urlPath': '/testuser/work/',
          'displayName': 'Work',
          'color': '#FF0000',
        },
      ];
      fakeService.cTag = 'same-ctag';
      fakeService.icsStringsToReturn = [
        'should not be fetched',
      ];

      final manager = SyncManager.forTesting(
        db,
        calDavServiceFactory: () async => fakeService,
      );
      await manager.performSync();

      // No new events should appear (cTag unchanged after push phase)
      final events = await db.getEvents();
      expect(events, isEmpty);
    });

    test('assigns null-calendarId events to first available calendar', () async {
      // Insert an event without a calendar
      await db.insertEvent(EventsCompanion.insert(
        uid: 'orphan-event',
        title: 'Orphan',
        startDate: DateTime(2024, 3, 15, 10),
        endDate: DateTime(2024, 3, 15, 11),
      ));

      final calId = await db.insertCalendar(CalendarsCompanion.insert(
        urlPath: '/testuser/work/',
        displayName: 'Work',
      ));

      fakeService.calendarsToReturn = [
        {
          'urlPath': '/testuser/work/',
          'displayName': 'Work',
          'color': '#FF0000',
        },
      ];
      fakeService.putEventResult = true;
      fakeService.cTag = 'ctag-1';

      final manager = SyncManager.forTesting(
        db,
        calDavServiceFactory: () async => fakeService,
      );
      await manager.performSync();

      // The orphan event should now be tied to the calendar
      final events = await db.getEvents();
      final orphan = events.firstWhere((e) => e.uid == 'orphan-event');
      expect(orphan.calendarId, calId);
    });

    test('handles sync errors gracefully without crashing', () async {
      final manager = SyncManager.forTesting(
        db,
        calDavServiceFactory: () async =>
            throw Exception('Network unreachable'),
      );

      // Should complete without throwing
      await manager.performSync();
    });

    test('closes CalDavService in finally block', () async {
      fakeService.calendarsToReturn = [];
      fakeService.createCalendarResult = true;

      final manager = SyncManager.forTesting(
        db,
        calDavServiceFactory: () async => fakeService,
      );
      await manager.performSync();

      expect(fakeService.closeCalled, isTrue);
    });
  });
}

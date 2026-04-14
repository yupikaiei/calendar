import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frelsi_cal/core/db/database.dart';

AppDatabase _createTestDb() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = _createTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  group('Events CRUD', () {
    test('insert and get events', () async {
      final id = await db.insertEvent(EventsCompanion.insert(
        uid: 'uid-1',
        title: 'Test Event',
        startDate: DateTime(2024, 3, 15, 10),
        endDate: DateTime(2024, 3, 15, 11),
      ));
      expect(id, greaterThan(0));

      final events = await db.getEvents();
      expect(events.length, 1);
      expect(events.first.uid, 'uid-1');
      expect(events.first.title, 'Test Event');
    });

    test('getEventById returns correct event', () async {
      final id = await db.insertEvent(EventsCompanion.insert(
        uid: 'uid-2',
        title: 'Find Me',
        startDate: DateTime(2024, 3, 15, 10),
        endDate: DateTime(2024, 3, 15, 11),
      ));

      final event = await db.getEventById(id);
      expect(event.title, 'Find Me');
      expect(event.uid, 'uid-2');
    });

    test('updateEvent modifies fields', () async {
      final id = await db.insertEvent(EventsCompanion.insert(
        uid: 'uid-3',
        title: 'Original',
        startDate: DateTime(2024, 3, 15, 10),
        endDate: DateTime(2024, 3, 15, 11),
      ));

      await db.updateEvent(EventsCompanion(
        id: Value(id),
        uid: const Value('uid-3'),
        title: const Value('Updated'),
        startDate: Value(DateTime(2024, 3, 15, 10)),
        endDate: Value(DateTime(2024, 3, 15, 11)),
      ));

      final event = await db.getEventById(id);
      expect(event.title, 'Updated');
    });

    test('deleteEvent removes it', () async {
      final id = await db.insertEvent(EventsCompanion.insert(
        uid: 'uid-4',
        title: 'Delete Me',
        startDate: DateTime(2024, 3, 15, 10),
        endDate: DateTime(2024, 3, 15, 11),
      ));

      final deleted = await db.deleteEvent(id);
      expect(deleted, 1);

      final events = await db.getEvents();
      expect(events, isEmpty);
    });
  });

  group('Calendars CRUD', () {
    test('insert and get calendars', () async {
      await db.insertCalendar(CalendarsCompanion.insert(
        urlPath: '/user/work/',
        displayName: 'Work',
        color: const Value('#FF0000'),
      ));

      final calendars = await db.getCalendars();
      expect(calendars.length, 1);
      expect(calendars.first.displayName, 'Work');
      expect(calendars.first.color, '#FF0000');
    });

    test('updateCalendar modifies fields', () async {
      await db.insertCalendar(CalendarsCompanion.insert(
        urlPath: '/user/work/',
        displayName: 'Work',
      ));

      final cals = await db.getCalendars();
      await db.updateCalendar(
        cals.first.copyWith(displayName: 'Work Updated', color: const Value('#00FF00')).toCompanion(true),
      );

      final updated = await db.getCalendars();
      expect(updated.first.displayName, 'Work Updated');
      expect(updated.first.color, '#00FF00');
    });

    test('deleteCalendar cascades to events and reminders', () async {
      final calId = await db.insertCalendar(CalendarsCompanion.insert(
        urlPath: '/user/work/',
        displayName: 'Work',
      ));

      final eventId = await db.insertEvent(EventsCompanion.insert(
        uid: 'ev-1',
        title: 'Work Event',
        startDate: DateTime(2024, 3, 15, 10),
        endDate: DateTime(2024, 3, 15, 11),
        calendarId: Value(calId),
      ));

      await db.insertReminder(RemindersCompanion.insert(
        eventId: eventId,
        minutesBefore: 30,
      ));

      await db.deleteCalendar(calId);

      expect(await db.getCalendars(), isEmpty);
      expect(await db.getEvents(), isEmpty);
    });
  });

  group('Reminders CRUD', () {
    test('insert and watch reminders for event', () async {
      final eventId = await db.insertEvent(EventsCompanion.insert(
        uid: 'ev-reminder',
        title: 'Reminded Event',
        startDate: DateTime(2024, 3, 15, 10),
        endDate: DateTime(2024, 3, 15, 11),
      ));

      await db.insertReminder(RemindersCompanion.insert(
        eventId: eventId,
        minutesBefore: 15,
      ));
      await db.insertReminder(RemindersCompanion.insert(
        eventId: eventId,
        minutesBefore: 30,
      ));

      final reminders = await db.watchRemindersForEvent(eventId).first;
      expect(reminders.length, 2);
    });

    test('deleteRemindersForEvent removes all', () async {
      final eventId = await db.insertEvent(EventsCompanion.insert(
        uid: 'ev-del-rem',
        title: 'Event',
        startDate: DateTime(2024, 3, 15, 10),
        endDate: DateTime(2024, 3, 15, 11),
      ));

      await db.insertReminder(RemindersCompanion.insert(
        eventId: eventId,
        minutesBefore: 15,
      ));
      await db.insertReminder(RemindersCompanion.insert(
        eventId: eventId,
        minutesBefore: 30,
      ));

      final deleted = await db.deleteRemindersForEvent(eventId);
      expect(deleted, 2);

      final reminders = await db.watchRemindersForEvent(eventId).first;
      expect(reminders, isEmpty);
    });
  });

  group('DeletedEvents', () {
    test('markEventDeleted and getDeletedEventUids', () async {
      await db.markEventDeleted('uid-deleted-1');
      await db.markEventDeleted('uid-deleted-2');

      final uids = await db.getDeletedEventUids();
      expect(uids, containsAll(['uid-deleted-1', 'uid-deleted-2']));
    });

    test('markEventDeleted is idempotent', () async {
      await db.markEventDeleted('uid-dup');
      await db.markEventDeleted('uid-dup');

      final uids = await db.getDeletedEventUids();
      expect(uids.where((u) => u == 'uid-dup').length, 1);
    });

    test('removeDeletedEventUid removes it', () async {
      await db.markEventDeleted('uid-remove');
      await db.removeDeletedEventUid('uid-remove');

      final uids = await db.getDeletedEventUids();
      expect(uids, isNot(contains('uid-remove')));
    });
  });

  group('Watchers', () {
    test('watchEvents emits after insert', () async {
      final stream = db.watchEvents();

      // First emission should be empty
      expect(await stream.first, isEmpty);

      await db.insertEvent(EventsCompanion.insert(
        uid: 'watch-1',
        title: 'Watched',
        startDate: DateTime(2024, 3, 15, 10),
        endDate: DateTime(2024, 3, 15, 11),
      ));

      // After insert, stream should emit again with the event
      final events = await stream.first;
      expect(events.length, 1);
      expect(events.first.title, 'Watched');
    });

    test('watchEventsWithCalendars joins calendar', () async {
      final calId = await db.insertCalendar(CalendarsCompanion.insert(
        urlPath: '/user/cal/',
        displayName: 'My Cal',
        color: const Value('#0000FF'),
      ));

      await db.insertEvent(EventsCompanion.insert(
        uid: 'joined-1',
        title: 'Joined Event',
        startDate: DateTime(2024, 3, 15, 10),
        endDate: DateTime(2024, 3, 15, 11),
        calendarId: Value(calId),
      ));

      final results = await db.watchEventsWithCalendars().first;
      expect(results.length, 1);
      expect(results.first.event.title, 'Joined Event');
      expect(results.first.calendar, isNotNull);
      expect(results.first.calendar!.displayName, 'My Cal');
    });

    test('watchEventsWithCalendars shows null calendar for unlinked event', () async {
      await db.insertEvent(EventsCompanion.insert(
        uid: 'unlinked-1',
        title: 'Unlinked Event',
        startDate: DateTime(2024, 3, 15, 10),
        endDate: DateTime(2024, 3, 15, 11),
      ));

      final results = await db.watchEventsWithCalendars().first;
      expect(results.length, 1);
      expect(results.first.calendar, isNull);
    });
  });
}

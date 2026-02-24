import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uid => text()(); // The CalDAV / iCal UID
  TextColumn get title => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  TextColumn get description => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get recurrenceRule => text().nullable()();
  IntColumn get calendarId => integer().nullable().references(Calendars, #id)();
}

class Calendars extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get urlPath =>
      text().unique()(); // The Radicale path, e.g. /magnosousa/frelsi/
  TextColumn get displayName => text()();
  TextColumn get color => text().nullable()(); // Hex string like #FF0000
  TextColumn get cTag => text().nullable()(); // The last sync ctag
}

class Reminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get eventId => integer().references(Events, #id)();
  IntColumn get minutesBefore => integer()();
}

class DeletedEvents extends Table {
  TextColumn get uid => text()();

  @override
  Set<Column> get primaryKey => {uid};
}

class EventWithCalendar {
  final Event event;
  final Calendar? calendar;

  EventWithCalendar({required this.event, this.calendar});
}

@DriftDatabase(tables: [Events, Reminders, DeletedEvents, Calendars])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from <= 1) {
          await m.createTable(reminders);
        }
        if (from <= 2) {
          await m.createTable(deletedEvents);
        }
        if (from <= 3) {
          await m.createTable(calendars);
          await m.addColumn(events, events.calendarId);
        }
      },
    );
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'frelsi_cal_db');
  }

  Stream<List<Event>> watchEvents() {
    return select(events).watch();
  }

  Stream<List<EventWithCalendar>> watchEventsWithCalendars() {
    final query = select(events).join([
      leftOuterJoin(calendars, calendars.id.equalsExp(events.calendarId)),
    ]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return EventWithCalendar(
          event: row.readTable(events),
          calendar: row.readTableOrNull(calendars),
        );
      }).toList();
    });
  }

  Future<List<Event>> getEvents() {
    return select(events).get();
  }

  Future<Event> getEventById(int id) {
    return (select(events)..where((e) => e.id.equals(id))).getSingle();
  }

  Future<int> insertEvent(EventsCompanion event) {
    return into(events).insert(event);
  }

  Future<bool> updateEvent(EventsCompanion event) {
    return update(events).replace(event);
  }

  Future<int> deleteEvent(int id) {
    return (delete(events)..where((e) => e.id.equals(id))).go();
  }

  Stream<List<Reminder>> watchRemindersForEvent(int eventId) {
    return (select(reminders)..where((r) => r.eventId.equals(eventId))).watch();
  }

  Future<int> insertReminder(RemindersCompanion reminder) {
    return into(reminders).insert(reminder);
  }

  Future<int> deleteRemindersForEvent(int eventId) {
    return (delete(reminders)..where((r) => r.eventId.equals(eventId))).go();
  }

  Future<List<String>> getDeletedEventUids() async {
    final rows = await select(deletedEvents).get();
    return rows.map((e) => e.uid).toList();
  }

  Future<int> markEventDeleted(String uid) {
    return into(deletedEvents).insert(
      DeletedEventsCompanion(uid: Value(uid)),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<int> removeDeletedEventUid(String uid) {
    return (delete(deletedEvents)..where((e) => e.uid.equals(uid))).go();
  }

  // --- Calendars ---

  Stream<List<Calendar>> watchCalendars() {
    return select(calendars).watch();
  }

  Future<List<Calendar>> getCalendars() {
    return select(calendars).get();
  }

  Future<int> insertCalendar(CalendarsCompanion calendar) {
    return into(calendars).insert(calendar, mode: InsertMode.insertOrReplace);
  }

  Future<bool> updateCalendar(CalendarsCompanion calendar) {
    return update(calendars).replace(calendar);
  }

  Future<int> deleteCalendar(int id) {
    return (delete(calendars)..where((c) => c.id.equals(id))).go();
  }
}

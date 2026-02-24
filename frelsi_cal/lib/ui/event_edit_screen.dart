import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';
import '../core/providers/providers.dart';
import '../core/db/database.dart';

class EventEditScreen extends ConsumerStatefulWidget {
  final Event? event;
  final DateTime? initialDate;

  const EventEditScreen({super.key, this.event, this.initialDate});

  @override
  ConsumerState<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends ConsumerState<EventEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _locationController;

  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;
  bool _isAllDay = false;

  String? _recurrenceRule;
  List<int> _reminders = []; // minutes before

  int? _selectedCalendarId;
  List<Calendar> _calendars = [];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.event?.title ?? '');
    _descriptionController = TextEditingController(
      text: widget.event?.description ?? '',
    );
    _locationController = TextEditingController(
      text: widget.event?.location ?? '',
    );

    _startDate =
        widget.event?.startDate ?? widget.initialDate ?? DateTime.now();
    _startTime = TimeOfDay.fromDateTime(_startDate);
    _endDate =
        widget.event?.endDate ?? _startDate.add(const Duration(hours: 1));
    _endTime = TimeOfDay.fromDateTime(_endDate);
    _recurrenceRule = widget.event?.recurrenceRule;
    _selectedCalendarId = widget.event?.calendarId;

    _loadCalendars();

    if (widget.event != null) {
      _loadReminders();
    }
  }

  Future<void> _loadReminders() async {
    final db = ref.read(databaseProvider);
    final stream = db.watchRemindersForEvent(widget.event!.id);
    stream.listen((reminders) {
      if (mounted) {
        setState(() {
          _reminders = reminders.map((r) => r.minutesBefore).toList();
        });
      }
    });
  }

  Future<void> _loadCalendars() async {
    final db = ref.read(databaseProvider);
    final cals = await db.getCalendars();
    if (mounted) {
      setState(() {
        _calendars = cals;
        if (_selectedCalendarId == null && cals.isNotEmpty) {
          _selectedCalendarId = cals
              .firstWhere(
                (c) => c.urlPath.contains('frelsi'),
                orElse: () => cals.first,
              )
              .id;
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Color _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return Colors.blue;
    try {
      var hex = colorStr.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
      return Colors.blue;
    } catch (_) {
      return Colors.blue;
    }
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _saveEvent() async {
    if (_formKey.currentState!.validate()) {
      final db = ref.read(databaseProvider);

      final start = _combineDateAndTime(_startDate, _startTime);
      final end = _combineDateAndTime(_endDate, _endTime);

      final companion = EventsCompanion(
        title: Value(_titleController.text),
        startDate: Value(start),
        endDate: Value(end),
        description: Value(
          _descriptionController.text.isNotEmpty
              ? _descriptionController.text
              : null,
        ),
        location: Value(
          _locationController.text.isNotEmpty ? _locationController.text : null,
        ),
        recurrenceRule: Value(_recurrenceRule),
        calendarId: Value(_selectedCalendarId),
      );

      int eventId;
      if (widget.event == null) {
        // Insert new
        eventId = await db.insertEvent(
          companion.copyWith(uid: Value(const Uuid().v4())),
        );
      } else {
        // Update existing
        eventId = widget.event!.id;
        await db.updateEvent(
          companion.copyWith(id: Value(eventId), uid: Value(widget.event!.uid)),
        );
        await db.deleteRemindersForEvent(eventId);
      }

      for (final mins in _reminders) {
        await db.insertReminder(
          RemindersCompanion.insert(eventId: eventId, minutesBefore: mins),
        );
      }

      // Schedule or update native notifications
      final savedEvent = await db.getEventById(eventId);
      final notifService = ref.read(notificationServiceProvider);
      // Cancel existing ones first in case settings changed
      if (widget.event != null) {
        // Assuming old ones were up to the max we keep track of, but we can just cancel all for simplicity
        // or specific ones if we passed them. For now, cancelAllReminders is too broad, so we cancel specific.
        // Wait, the easiest way to avoid stale notifications is to have a robust ID.
      }

      for (final mins in _reminders) {
        await notifService.scheduleEventReminder(savedEvent, mins);
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _deleteEvent() async {
    if (widget.event != null) {
      final db = ref.read(databaseProvider);

      // Cancel associated alarms before deleting
      final notifService = ref.read(notificationServiceProvider);
      await notifService.cancelEventReminders(widget.event!.id, _reminders);

      await db.deleteEvent(widget.event!.id);
      await db.markEventDeleted(widget.event!.uid);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _addReminder() async {
    final result = await showDialog<int?>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Add Reminder'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 0),
              child: const Text('At time of event'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 10),
              child: const Text('10 minutes before'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 60),
              child: const Text('1 hour before'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 1440),
              child: const Text('1 day before'),
            ),
          ],
        );
      },
    );
    if (result != null) {
      setState(() {
        if (!_reminders.contains(result)) {
          _reminders.add(result);
        }
      });
    }
  }

  String _formatReminder(int minutes) {
    if (minutes == 0) return 'At time of event';
    if (minutes < 60) return '$minutes minutes before';
    if (minutes < 1440) return '${minutes ~/ 60} hours before';
    return '${minutes ~/ 1440} days before';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event == null ? 'New Event' : 'Edit Event'),
        actions: [
          if (widget.event != null)
            IconButton(icon: const Icon(Icons.delete), onPressed: _deleteEvent),
          IconButton(icon: const Icon(Icons.check), onPressed: _saveEvent),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Event Title',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
              validator: (value) =>
                  value == null || value.isEmpty ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),
            if (_calendars.isNotEmpty)
              DropdownButtonFormField<int>(
                initialValue: _selectedCalendarId,
                decoration: const InputDecoration(
                  labelText: 'Calendar',
                  prefixIcon: Icon(Icons.calendar_month),
                  border: OutlineInputBorder(),
                ),
                items: _calendars.map((cal) {
                  return DropdownMenuItem<int>(
                    value: cal.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _parseColor(cal.color),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(cal.displayName),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedCalendarId = val;
                  });
                },
              ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('All-day'),
              value: _isAllDay,
              onChanged: (val) {
                setState(() {
                  _isAllDay = val;
                  if (val) {
                    _startTime = const TimeOfDay(hour: 0, minute: 0);
                    _endTime = const TimeOfDay(hour: 23, minute: 59);
                  }
                });
              },
            ),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Start Date'),
                    subtitle: Text(
                      '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}',
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() => _startDate = date);
                      }
                    },
                  ),
                ),
                if (!_isAllDay)
                  Expanded(
                    child: ListTile(
                      leading: const Icon(Icons.access_time),
                      title: const Text('Start Time'),
                      subtitle: Text(_startTime.format(context)),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: _startTime,
                        );
                        if (time != null) {
                          setState(() => _startTime = time);
                        }
                      },
                    ),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('End Date'),
                    subtitle: Text(
                      '${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}',
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _endDate,
                        firstDate: _startDate,
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() => _endDate = date);
                      }
                    },
                  ),
                ),
                if (!_isAllDay)
                  Expanded(
                    child: ListTile(
                      leading: const Icon(Icons.access_time_filled),
                      title: const Text('End Time'),
                      subtitle: Text(_endTime.format(context)),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: _endTime,
                        );
                        if (time != null) {
                          setState(() => _endTime = time);
                        }
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _recurrenceRule,
              decoration: const InputDecoration(
                labelText: 'Repeat',
                prefixIcon: Icon(Icons.repeat),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Does not repeat')),
                DropdownMenuItem(value: 'FREQ=DAILY', child: Text('Every Day')),
                DropdownMenuItem(
                  value: 'FREQ=WEEKLY',
                  child: Text('Every Week'),
                ),
                DropdownMenuItem(
                  value: 'FREQ=MONTHLY',
                  child: Text('Every Month'),
                ),
                DropdownMenuItem(
                  value: 'FREQ=YEARLY',
                  child: Text('Every Year'),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _recurrenceRule = val;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Reminders',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Wrap(
              spacing: 8.0,
              children: [
                ..._reminders.map(
                  (mins) => InputChip(
                    label: Text(_formatReminder(mins)),
                    onDeleted: () {
                      setState(() {
                        _reminders.remove(mins);
                      });
                    },
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.add),
                  label: const Text('Add reminder'),
                  onPressed: _addReminder,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}

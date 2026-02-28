import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as drift;
import '../core/providers/providers.dart';
import '../core/network/caldav_service.dart';
import '../core/db/database.dart';
import '../core/sync/sync_manager.dart';
import '../core/sync/ical_parser.dart';
import 'package:timezone/standalone.dart' as tz;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _serverUrlController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverUrlController.text = prefs.getString('server_url') ?? '';
      _usernameController.text = prefs.getString('username') ?? '';
      _passwordController.text = prefs.getString('password') ?? '';
    });
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', _serverUrlController.text.trim());
      await prefs.setString('username', _usernameController.text.trim());
      await prefs.setString('password', _passwordController.text.trim());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully')),
        );
      }
    }
  }

  void _showCreateCalendarDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Calendar'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Calendar Name',
              hintText: 'e.g. Work, Home',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context);
                  await _createNewCalendar(name);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createNewCalendar(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('server_url') ?? '';
    final username = prefs.getString('username') ?? '';
    final password = prefs.getString('password') ?? '';

    if (serverUrl.isEmpty || username.isEmpty) return;

    final service = CalDavService(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );

    // Create a URL-safe path from the name
    final pathName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');
    final calendarPath = '/$username/$pathName/';

    try {
      final success = await service.createCalendar(calendarPath, name);
      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Calendar "$name" created!')));
        // Trigger a sync to pull it into the local DB
        ref.read(syncManagerProvider).performSync();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create calendar on Radicale.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _importCalendar() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ics'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String icsData = await file.readAsString();

        final parsedEvents = ICalParser.parseEvents(icsData);
        if (parsedEvents.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No events found in this file.')),
            );
          }
          return;
        }

        // 1. Create a local calendar designated for imports (if it doesn't exist)
        final db = ref.read(databaseProvider);
        final importCalId = await db
            .into(db.calendars)
            .insert(
              CalendarsCompanion.insert(
                urlPath:
                    '/local/imported/${DateTime.now().millisecondsSinceEpoch}/',
                displayName: 'Imported Calendar',
                color: const drift.Value('#4CAF50'),
                cTag: const drift.Value(''),
              ),
            );

        // 2. Insert all the parsed events into the database
        for (var eventCompanion in parsedEvents) {
          await db
              .into(db.events)
              .insert(
                eventCompanion.copyWith(calendarId: drift.Value(importCalId)),
              );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Imported ${parsedEvents.length} events successfully!',
              ),
            ),
          );
          // Sync just to refresh the UI streams if necessary
          ref.read(syncManagerProvider).performSync();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to import ICS: $e')));
      }
    }
  }

  void _showRenameCalendarDialog(Calendar cal) {
    final nameController = TextEditingController(text: cal.displayName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Calendar'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Calendar Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isNotEmpty && newName != cal.displayName) {
                  Navigator.pop(context);
                  await _renameCalendar(cal, newName);
                } else {
                  Navigator.pop(context);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _renameCalendar(Calendar cal, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('server_url') ?? '';
    final username = prefs.getString('username') ?? '';
    final password = prefs.getString('password') ?? '';

    if (serverUrl.isEmpty || username.isEmpty) return;

    final service = CalDavService(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );

    try {
      bool success = false;
      if (cal.urlPath.startsWith('/local/')) {
        success = true;
      } else {
        success = await service.updateCalendarName(cal.urlPath, newName);
      }
      if (success && mounted) {
        final db = ref.read(databaseProvider);
        await db.updateCalendar(
          cal.copyWith(displayName: newName).toCompanion(true),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Calendar renamed!')));
        ref.read(syncManagerProvider).performSync();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to rename calendar on server.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _confirmDeleteCalendar(Calendar cal) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Calendar?'),
          content: Text(
            'Are you sure you want to delete "${cal.displayName}"? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context);
                await _deleteCalendar(cal);
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteCalendar(Calendar cal) async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('server_url') ?? '';
    final username = prefs.getString('username') ?? '';
    final password = prefs.getString('password') ?? '';

    if (serverUrl.isEmpty || username.isEmpty) return;

    final service = CalDavService(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );

    try {
      bool success = false;
      if (cal.urlPath.startsWith('/local/')) {
        success = true;
      } else {
        success = await service.deleteCalendar(cal.urlPath);
      }
      if (success && mounted) {
        final db = ref.read(databaseProvider);
        await db.deleteCalendar(cal.id);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Calendar deleted.')));
        ref.read(syncManagerProvider).performSync();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete calendar on server.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
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

  Future<void> _updateColor(Calendar cal, Color color) async {
    final hexString =
        '#${color.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';

    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('server_url') ?? '';
    final username = prefs.getString('username') ?? '';
    final password = prefs.getString('password') ?? '';

    if (serverUrl.isEmpty || username.isEmpty) return;

    final service = CalDavService(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );

    try {
      bool success = false;
      if (cal.urlPath.startsWith('/local/')) {
        success = true;
      } else {
        success = await service.updateCalendarColor(cal.urlPath, hexString);
      }
      if (success && mounted) {
        final db = ref.read(databaseProvider);
        await db.updateCalendar(
          cal.copyWith(color: drift.Value(hexString)).toCompanion(true),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calendar color updated!')),
        );
        ref.read(syncManagerProvider).performSync();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update color on server.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showColorPicker(Calendar cal) {
    final colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.grey,
      Colors.blueGrey,
      Colors.black,
    ];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Calendar Color'),
          content: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((color) {
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _updateColor(cal, color);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            const Text(
              'CalDAV Server Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _serverUrlController,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              validator: (val) =>
                  val == null || val.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (val) =>
                  val == null || val.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              validator: (val) =>
                  val == null || val.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveSettings,
              child: const Text('Save Connections'),
            ),

            const Divider(height: 48),

            const Text(
              'Timezone Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Consumer(
              builder: (context, ref, child) {
                final currentTz = ref.watch(secondaryTimezoneProvider);
                final locations = tz.timeZoneDatabase.locations.keys.toList()
                  ..sort();

                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Secondary Timezone',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.language),
                  ),
                  initialValue: currentTz,
                  hint: const Text('None (Local Time Only)'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('None (Local Time Only)'),
                    ),
                    ...locations.map(
                      (loc) => DropdownMenuItem(value: loc, child: Text(loc)),
                    ),
                  ],
                  onChanged: (String? newValue) {
                    ref
                        .read(secondaryTimezoneProvider.notifier)
                        .setTimezone(newValue);
                  },
                );
              },
            ),

            const Divider(height: 48),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'My Calendars',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.file_download),
                      onPressed: _importCalendar,
                      tooltip: 'Import .ics File',
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _showCreateCalendarDialog,
                      tooltip: 'Create New Calendar',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Calendar>>(
              stream: ref.watch(databaseProvider).watchCalendars(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final calendars = snapshot.data ?? [];
                if (calendars.isEmpty) {
                  return const Text(
                    'No calendars synced yet. Tap Sync on the home screen or create one.',
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: calendars.length,
                  itemBuilder: (context, index) {
                    final cal = calendars[index];
                    return ListTile(
                      leading: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _parseColor(cal.color),
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(cal.displayName),
                      subtitle: Text(cal.urlPath),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'color') {
                            _showColorPicker(cal);
                          } else if (value == 'rename') {
                            _showRenameCalendarDialog(cal);
                          } else if (value == 'delete') {
                            _confirmDeleteCalendar(cal);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'color',
                            child: Text('Change Color'),
                          ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              'Delete',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),

            const Divider(height: 48),

            const Text(
              'Appearance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Theme'),
              subtitle: const Text('System Default'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // TODO: Show theme picker dialog
              },
            ),
          ],
        ),
      ),
    );
  }
}

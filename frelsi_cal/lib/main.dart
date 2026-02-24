import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'core/providers/providers.dart';
import 'core/sync/sync_manager.dart';
import 'ui/calendar_home_screen.dart';

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });

  runApp(const ProviderScope(child: FrelsiCalApp()));
}

class FrelsiCalApp extends ConsumerStatefulWidget {
  const FrelsiCalApp({super.key});

  @override
  ConsumerState<FrelsiCalApp> createState() => _FrelsiCalAppState();
}

class _FrelsiCalAppState extends ConsumerState<FrelsiCalApp> {
  @override
  void initState() {
    super.initState();
    // Initialize the sync manager immediately so it starts listening to lifecycle events
    ref.read(syncManagerProvider);
    // Initialize notification service immediately so permissions can be requested
    ref.read(notificationServiceProvider).init();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frelsi Cal',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const CalendarHomeScreen(),
    );
  }
}

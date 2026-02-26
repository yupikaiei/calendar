import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logging/logging.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'core/providers/providers.dart';
import 'core/sync/sync_manager.dart';
import 'ui/app_splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF03DAC6),
          surface: Color(0xFF1E1E2C),
          // We can't map 'background' easily in all material3 versions, but we can set scaffoldBackgroundColor
          error: Color(0xFFFF4B4B),
        ),
        scaffoldBackgroundColor: const Color(0xFF12121D),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const AppSplashScreen(),
    );
  }
}

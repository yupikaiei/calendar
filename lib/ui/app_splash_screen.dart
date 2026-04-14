import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'calendar_home_screen.dart';
import 'frelsi_wordmark.dart';

class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({super.key});

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen> {
  @override
  void initState() {
    super.initState();
    // Defer heavy work until after the first frame so the splash renders immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final sw = Stopwatch()..start();

    // Heavy initialisations – now run while the splash is already visible
    tz.initializeTimeZones();

    // Guarantee the splash is visible for at least 3 seconds
    final remaining = 3000 - sw.elapsedMilliseconds;
    if (remaining > 0) {
      await Future.delayed(Duration(milliseconds: remaining));
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const CalendarHomeScreen(),
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121D),
      body: Center(child: const FrelsiWordmark()),
    );
  }
}

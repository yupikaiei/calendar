import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database.dart';
import '../network/caldav_service.dart';
import '../services/secure_config_service.dart';
export '../notifications/notification_service.dart';
export '../services/secure_config_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

class SecondaryTimezoneNotifier extends Notifier<String?> {
  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('secondary_timezone');
  }

  Future<void> setTimezone(String? tzName) async {
    final prefs = await SharedPreferences.getInstance();
    if (tzName == null || tzName.isEmpty) {
      await prefs.remove('secondary_timezone');
    } else {
      await prefs.setString('secondary_timezone', tzName);
    }
    state = tzName;
  }
}

final secondaryTimezoneProvider =
    NotifierProvider<SecondaryTimezoneNotifier, String?>(() {
      return SecondaryTimezoneNotifier();
    });

/// Shared factory that builds a [CalDavService] from persisted settings.
/// Returns `null` when the required settings are missing.
Future<CalDavService?> createCalDavServiceFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  final secure = SecureConfigService();
  await secure.ensureMigrated();
  final serverUrl = prefs.getString('server_url') ?? '';
  final username = prefs.getString('username') ?? '';
  final password = await secure.read('password');

  if (serverUrl.isEmpty || username.isEmpty) return null;

  return CalDavService(
    serverUrl: serverUrl,
    username: username,
    password: password,
  );
}

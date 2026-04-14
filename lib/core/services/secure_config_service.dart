import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final secureConfigProvider = Provider<SecureConfigService>((ref) {
  return SecureConfigService();
});

class SecureConfigService {
  final FlutterSecureStorage _secureStorage;
  static const _migratedKey = '_credentials_migrated';

  SecureConfigService({FlutterSecureStorage? storage})
      : _secureStorage = storage ?? const FlutterSecureStorage();

  // Keys stored securely
  static const _secureKeys = ['password', 'ai_api_key', 'stt_api_key'];

  /// Ensures credentials are migrated from SharedPreferences to secure storage.
  /// Safe to call multiple times — migration only runs once.
  Future<void> ensureMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedKey) == true) return;

    for (final key in _secureKeys) {
      final value = prefs.getString(key);
      if (value != null && value.isNotEmpty) {
        await _secureStorage.write(key: key, value: value);
        await prefs.remove(key);
      }
    }
    await prefs.setBool(_migratedKey, true);
  }

  Future<String> read(String key) async {
    return await _secureStorage.read(key: key) ?? '';
  }

  Future<void> write(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  Future<void> delete(String key) async {
    await _secureStorage.delete(key: key);
  }
}

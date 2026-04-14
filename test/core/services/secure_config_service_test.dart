import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frelsi_cal/core/services/secure_config_service.dart';

/// In-memory fake for FlutterSecureStorage.
class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }
}

void main() {
  late FakeSecureStorage fakeStorage;
  late SecureConfigService service;

  setUp(() {
    fakeStorage = FakeSecureStorage();
    service = SecureConfigService(storage: fakeStorage);
  });

  group('ensureMigrated', () {
    test('moves credentials from SharedPreferences to secure storage', () async {
      SharedPreferences.setMockInitialValues({
        'password': 'secret123',
        'ai_api_key': 'key-abc',
        'stt_api_key': 'key-xyz',
      });

      await service.ensureMigrated();

      // Values should now be in secure storage
      expect(await service.read('password'), 'secret123');
      expect(await service.read('ai_api_key'), 'key-abc');
      expect(await service.read('stt_api_key'), 'key-xyz');

      // Values should be removed from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('password'), isNull);
      expect(prefs.getString('ai_api_key'), isNull);
      expect(prefs.getString('stt_api_key'), isNull);

      // Migration flag should be set
      expect(prefs.getBool('_credentials_migrated'), isTrue);
    });

    test('is idempotent — second call is a no-op', () async {
      SharedPreferences.setMockInitialValues({'password': 'secret123'});

      await service.ensureMigrated();
      // Write a new value directly to prefs after migration
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('password', 'should-not-migrate');

      await service.ensureMigrated();

      // Secure storage should still have original migrated value
      expect(await service.read('password'), 'secret123');
    });

    test('skips empty values', () async {
      SharedPreferences.setMockInitialValues({
        'password': '',
        'ai_api_key': 'valid-key',
      });

      await service.ensureMigrated();

      expect(await service.read('password'), '');
      expect(await service.read('ai_api_key'), 'valid-key');
    });

    test('skips missing keys', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await service.ensureMigrated();

      expect(await service.read('password'), '');
      expect(await service.read('ai_api_key'), '');
      expect(await service.read('stt_api_key'), '');
    });
  });

  group('read', () {
    test('returns empty string for missing key', () async {
      expect(await service.read('nonexistent'), '');
    });
  });

  group('write + read', () {
    test('round-trip stores and retrieves value', () async {
      await service.write('my_key', 'my_value');
      expect(await service.read('my_key'), 'my_value');
    });
  });

  group('delete', () {
    test('removes a stored key', () async {
      await service.write('my_key', 'my_value');
      await service.delete('my_key');
      expect(await service.read('my_key'), '');
    });
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
export '../notifications/notification_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

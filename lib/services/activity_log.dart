import '../core/app_state.dart';
import '../core/db.dart';

class ActivityLog {
  /// Records who did what. Pass [s] when inside a transaction.
  static Future<void> add(
    String action, {
    String? entity,
    String? entityId,
    String? detail,
    Store? s,
  }) async {
    final u = AppState.instance.user;
    await (s ?? Db.instance.s).insert('activity_logs', {
      'employee_id': u?.id,
      'employee_name': u?.name,
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'detail': detail,
    });
  }
}

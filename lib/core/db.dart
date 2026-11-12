import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'ids.dart';
import 'migrations.dart';

typedef DbRow = Map<String, Object?>;

double asDouble(Object? v) => v == null ? 0 : (v as num).toDouble();
int asInt(Object? v) => v == null ? 0 : (v as num).toInt();
String? asStr(Object? v) => v?.toString();
bool asBool(Object? v) => v != null && asInt(v) == 1;

/// Device-local values that must never be synced between phones
/// (device id, printer, last backup time, ...).
class Local {
  static late SharedPreferences prefs;
}

/// Thin helper over a sqflite executor (database or transaction).
/// Every write stamps the common sync columns.
class Store {
  Store(this.ex, {this.autoNotify = false});

  final DatabaseExecutor ex;
  final bool autoNotify;

  Future<String> insert(String table, DbRow values) async {
    final now = nowMs();
    final row = <String, Object?>{...values};
    row['id'] ??= newId();
    row['created_at'] ??= now;
    row['updated_at'] = now;
    row['device_id'] ??= Db.instance.deviceId;
    await ex.insert(table, row);
    if (autoNotify) Db.instance.notifyChanged();
    return row['id'] as String;
  }

  Future<void> update(String table, String id, DbRow values) async {
    await ex.update(table, {...values, 'updated_at': nowMs()}, where: 'id = ?', whereArgs: [id]);
    if (autoNotify) Db.instance.notifyChanged();
  }

  Future<void> softDelete(String table, String id) => update(table, id, {'deleted_at': nowMs()});

  Future<List<DbRow>> q(String sql, [List<Object?>? args]) => ex.rawQuery(sql, args);

  Future<DbRow?> one(String sql, [List<Object?>? args]) async {
    final r = await ex.rawQuery(sql, args);
    return r.isEmpty ? null : r.first;
  }

  Future<DbRow?> byId(String table, String id) =>
      one('SELECT * FROM $table WHERE id = ?', [id]);

  /// Returns the first column of the first row as a double (0 when null).
  Future<double> scalar(String sql, [List<Object?>? args]) async {
    final r = await one(sql, args);
    if (r == null || r.isEmpty) return 0;
    return asDouble(r.values.first);
  }
}

class Db {
  Db._();
  static final Db instance = Db._();

  /// Database file name. Tests point this at their own file.
  static String fileName = 'bizpos.db';

  Database? _db;
  late String deviceId;

  /// Incremented after every write. Screens listen to this to refresh.
  final ValueNotifier<int> changes = ValueNotifier(0);

  Database get raw => _db!;

  /// Read/write helper that notifies listeners after each write.
  Store get s => Store(raw, autoNotify: true);

  Future<void> init() async {
    Local.prefs = await SharedPreferences.getInstance();
    var id = Local.prefs.getString('device_id');
    if (id == null) {
      id = newId();
      await Local.prefs.setString('device_id', id);
    }
    deviceId = id;
    await _open();
  }

  Future<String> path() async => p.join(await getDatabasesPath(), fileName);

  Future<void> _open() async {
    _db = await openDatabase(
      await path(),
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = OFF');
      },
      onCreate: (db, version) async {
        await _migrate(db, 0, version);
      },
      onUpgrade: (db, oldV, newV) async {
        await _migrate(db, oldV, newV);
      },
    );
  }

  Future<void> _migrate(Database db, int from, int to) async {
    for (var v = from + 1; v <= to; v++) {
      final steps = migrations[v];
      if (steps == null) throw StateError('Missing migration for version $v');
      final batch = db.batch();
      for (final sql in steps) {
        batch.execute(sql);
      }
      await batch.commit(noResult: true);
    }
  }

  /// Deletes every row and recreates an empty database. Used by "replace" restores.
  Future<void> wipe() async {
    await _db?.close();
    await deleteDatabase(await path());
    await _open();
    notifyChanged();
  }

  Future<T> tx<T>(Future<T> Function(Store s) fn) async {
    final result = await raw.transaction((txn) => fn(Store(txn)));
    notifyChanged();
    return result;
  }

  /// Asks screens to reload without marking data as changed.
  void refresh() => changes.value++;

  void notifyChanged() {
    changes.value++;
    Local.prefs.setInt('last_change_at', nowMs());
  }

  // ------------------------------------------------------------ settings
  Future<Map<String, String>> allSettings() async {
    final rows = await raw.rawQuery('SELECT key, value FROM settings');
    return {for (final r in rows) r['key'] as String: (r['value'] ?? '') as String};
  }

  Future<void> setSetting(String key, String value) async {
    await raw.insert(
      'settings',
      {'key': key, 'value': value, 'updated_at': nowMs()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChanged();
  }
}

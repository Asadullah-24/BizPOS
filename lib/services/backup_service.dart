import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/ids.dart';
import '../core/migrations.dart';
import 'inventory_service.dart';
import 'product_service.dart';

class MergeResult {
  int inserted = 0;
  int updated = 0;
  int skipped = 0;
  int images = 0;

  @override
  String toString() => '$inserted new, $updated updated, $skipped kept (local copy was newer)';
}

/// Backups are a gzip-compressed JSON snapshot of every synced table.
///
/// Restoring merges instead of overwriting:
/// * Every row has a unique id, so sales, payments and stock movements made on
///   different phones are all kept. No transaction can overwrite another one.
/// * When the same row exists on both sides (for example a product edited on
///   two phones), the copy with the newer updated_at wins.
/// * Deletes are soft (deleted_at), so they travel with the backup too.
/// * Stock and balances are recalculated from the merged transactions.
class BackupService {
  static const format = 'bizpos-backup';

  static Future<Map<String, dynamic>> snapshot({bool includeImages = true}) async {
    final db = Db.instance.raw;
    final tables = <String, dynamic>{};
    for (final t in syncTables) {
      tables[t] = await db.rawQuery('SELECT * FROM $t');
    }
    final settings = await db.rawQuery('SELECT * FROM settings');
    final images = <String, String>{};
    if (includeImages) {
      for (final name in await imageNames()) {
        final f = await ImageStore.file(name);
        if (f != null) images[name] = base64Encode(await f.readAsBytes());
      }
    }
    return {
      'format': format,
      'schema': schemaVersion,
      'device_id': Db.instance.deviceId,
      'business_name': AppState.instance.businessName,
      'created_at': nowMs(),
      'tables': tables,
      'settings': settings,
      'images': images,
    };
  }

  static Future<List<String>> imageNames() async {
    final rows = await Db.instance.raw.rawQuery(
        "SELECT DISTINCT image FROM products WHERE image IS NOT NULL AND image != '' AND deleted_at IS NULL");
    return rows.map((r) => r['image'] as String).toList();
  }

  static List<int> encode(Map<String, dynamic> data) => gzip.encode(utf8.encode(jsonEncode(data)));

  static Map<String, dynamic> decode(List<int> bytes) {
    List<int> raw;
    try {
      raw = gzip.decode(bytes);
    } catch (_) {
      raw = bytes; // Plain JSON backup.
    }
    final data = jsonDecode(utf8.decode(raw));
    if (data is! Map<String, dynamic> || data['format'] != format) {
      throw const FormatException('This file is not a BizPOS backup.');
    }
    final v = (data['schema'] as num?)?.toInt() ?? 0;
    if (v > schemaVersion) {
      throw const FormatException('This backup was made by a newer version of the app. Update the app first.');
    }
    return data;
  }

  /// Writes a backup file to the temporary folder and returns it (for sharing).
  static Future<File> exportFile({bool includeImages = true}) async {
    final data = await snapshot(includeImages: includeImages);
    final dir = await getTemporaryDirectory();
    final name = 'BizPOS-backup-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.bizpos';
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(encode(data), flush: true);
    return f;
  }

  static Future<MergeResult> importFile(File f, {bool replace = false}) async {
    final data = decode(await f.readAsBytes());
    return replace ? replaceWith(data) : merge(data);
  }

  static Future<MergeResult> replaceWith(Map<String, dynamic> data) async {
    await Db.instance.wipe();
    return merge(data);
  }

  static Future<MergeResult> merge(Map<String, dynamic> data) async {
    final result = MergeResult();
    final tables = (data['tables'] as Map?) ?? {};
    final db = Db.instance.raw;

    await db.transaction((txn) async {
      for (final t in syncTables) {
        final rows = tables[t];
        if (rows is! List || rows.isEmpty) continue;
        final cols = (await txn.rawQuery('PRAGMA table_info($t)')).map((c) => c['name'] as String).toSet();
        final local = {
          for (final r in await txn.rawQuery('SELECT id, updated_at FROM $t'))
            r['id'] as String: asInt(r['updated_at'])
        };
        final batch = txn.batch();
        for (final raw in rows) {
          final row = <String, Object?>{};
          (raw as Map).forEach((k, v) {
            if (cols.contains(k)) row[k as String] = v;
          });
          final id = row['id'] as String?;
          if (id == null) continue;
          final remoteUpdated = asInt(row['updated_at']);
          final localUpdated = local[id];
          if (localUpdated == null) {
            batch.insert(t, row);
            result.inserted++;
          } else if (remoteUpdated > localUpdated) {
            batch.update(t, row, where: 'id = ?', whereArgs: [id]);
            result.updated++;
          } else {
            result.skipped++;
          }
        }
        await batch.commit(noResult: true);
      }

      final settings = data['settings'];
      if (settings is List) {
        final local = {
          for (final r in await txn.rawQuery('SELECT key, updated_at FROM settings'))
            r['key'] as String: asInt(r['updated_at'])
        };
        for (final raw in settings) {
          final m = raw as Map;
          final key = m['key'] as String;
          final upd = asInt(m['updated_at']);
          if ((local[key] ?? -1) < upd) {
            await txn.rawInsert(
              'INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?, ?, ?)',
              [key, m['value'], upd],
            );
          }
        }
      }
      await InventoryService.refreshAllStock(Store(txn));
    });

    final images = data['images'];
    if (images is Map) {
      for (final e in images.entries) {
        final name = e.key as String;
        if (await ImageStore.file(name) == null) {
          await ImageStore.writeBytes(name, base64Decode(e.value as String));
          result.images++;
        }
      }
    }

    Db.instance.notifyChanged();
    await AppState.instance.load();
    return result;
  }
}

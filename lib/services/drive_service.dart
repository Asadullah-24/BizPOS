import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../core/db.dart';
import 'profile_service.dart';
import '../core/ids.dart';
import 'backup_service.dart';
import 'product_service.dart';

/// Google Drive backup in the app's hidden appDataFolder.
///
/// * Each phone uploads its own file: bizpos-<deviceId>.bizpos (data only).
/// * Product photos are uploaded once each as img-<name>.
/// * "Sync / Restore" downloads every phone's file and merges it, so moving to
///   a new phone or running two phones on one account loses nothing.
class DriveService extends ChangeNotifier {
  DriveService._();
  static final DriveService instance = DriveService._();

  final GoogleSignIn _gsi = GoogleSignIn(scopes: [drive.DriveApi.driveAppdataScope]);
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _timer;
  bool busy = false;
  String? lastError;

  GoogleSignInAccount? get account => _gsi.currentUser;
  bool get enabled => Local.prefs.getBool(Local.k('drive_enabled')) ?? false;
  String? get email => Local.prefs.getString(Local.k('drive_email'));
  int get lastBackupAt => Local.prefs.getInt(Local.k('last_backup_at')) ?? 0;
  int get lastChangeAt => Local.prefs.getInt(Local.k('last_change_at')) ?? 0;
  bool get hasPendingChanges => lastChangeAt > lastBackupAt;

  /// Each store on this phone has its own backup files (see ProfileService.driveTag).
  String get _fileName => 'bizpos-${ProfileService.instance.driveTag}${Db.instance.deviceId}.bizpos';

  bool _isMine(String name) {
    final tag = ProfileService.instance.driveTag;
    if (!name.startsWith('bizpos-')) return false;
    if (tag.isEmpty) return !RegExp(r'^bizpos-u').hasMatch(name);
    return name.startsWith('bizpos-$tag');
  }

  /// Starts automatic backup: whenever the phone comes online, and every 15
  /// minutes while the app is open, if something changed since the last backup.
  Future<void> start() async {
    if (enabled) {
      try {
        await _gsi.signInSilently();
      } catch (_) {}
    }
    try {
      _sub ??= Connectivity().onConnectivityChanged.listen(
        (results) {
          if (results.any((r) => r != ConnectivityResult.none)) autoBackup();
        },
        onError: (Object _) {},
      );
    } catch (_) {}
    _timer ??= Timer.periodic(const Duration(minutes: 15), (_) => autoBackup());
    unawaited(autoBackup());
  }

  /// Stops automatic backup (used when the app is torn down, and in tests).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _sub?.cancel();
    _sub = null;
  }

  Future<bool> signIn() async {
    try {
      final acc = await _gsi.signIn();
      if (acc == null) return false;
      await Local.prefs.setBool(Local.k('drive_enabled'), true);
      await Local.prefs.setString(Local.k('drive_email'), acc.email);
      lastError = null;
      notifyListeners();
      return true;
    } catch (e) {
      lastError = '$e';
      notifyListeners();
      return false;
    }
  }

  /// PIN recovery: true when the user signs in with the same Google account
  /// that holds this business's backup.
  Future<bool> verifyBackupAccount() async {
    final expected = email;
    if (!enabled || expected == null) return false;
    try {
      final acc = await _gsi.signIn();
      return acc != null && acc.email.toLowerCase() == expected.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _gsi.signOut();
    } catch (_) {}
    await Local.prefs.setBool(Local.k('drive_enabled'), false);
    await Local.prefs.remove(Local.k('drive_email'));
    notifyListeners();
  }

  Future<drive.DriveApi?> _api({bool interactive = false}) async {
    var acc = _gsi.currentUser;
    acc ??= await _gsi.signInSilently();
    if (acc == null && interactive) acc = await _gsi.signIn();
    if (acc == null) return null;
    final client = await _gsi.authenticatedClient();
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  Future<void> autoBackup() async {
    if (!enabled || busy || !hasPendingChanges) return;
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.every((r) => r == ConnectivityResult.none)) return;
      await backupNow();
    } catch (_) {
      // Retried on the next trigger.
    }
  }

  Future<void> backupNow({bool interactive = false}) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      final api = await _api(interactive: interactive);
      if (api == null) throw StateError('Sign in with Google first.');
      final startedAt = nowMs();
      final files = await _list(api);

      // Photos: upload only the ones Drive does not have yet.
      final remoteNames = files.map((f) => f.name).toSet();
      for (final name in await BackupService.imageNames()) {
        if (remoteNames.contains('img-$name')) continue;
        final f = await ImageStore.file(name);
        if (f == null) continue;
        final bytes = await f.readAsBytes();
        await _upload(api, 'img-$name', bytes, null);
      }

      final data = BackupService.encode(await BackupService.snapshot(includeImages: false));
      final existing = files.where((f) => f.name == _fileName).toList();
      await _upload(api, _fileName, data, existing.isEmpty ? null : existing.first.id);
      await Local.prefs.setInt(Local.k('last_backup_at'), startedAt);
      lastError = null;
    } catch (e) {
      lastError = '$e';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Downloads all phones' backups from Drive and merges them into this phone.
  Future<MergeResult> restoreAndMerge() async {
    if (busy) throw StateError('A backup is already running.');
    busy = true;
    notifyListeners();
    final total = MergeResult();
    try {
      final api = await _api(interactive: true);
      if (api == null) throw StateError('Sign in with Google first.');
      final files = await _list(api);
      final dataFiles = files.where((f) => _isMine(f.name ?? '')).toList();
      if (dataFiles.isEmpty) throw StateError('No backup found on this Google account.');
      for (final f in dataFiles) {
        final bytes = await _download(api, f.id!);
        final r = await BackupService.merge(BackupService.decode(bytes));
        total.inserted += r.inserted;
        total.updated += r.updated;
        total.skipped += r.skipped;
      }
      final have = await BackupService.imageNames();
      for (final name in have) {
        if (await ImageStore.file(name) != null) continue;
        final match = files.where((f) => f.name == 'img-$name').toList();
        if (match.isEmpty) continue;
        await ImageStore.writeBytes(name, await _download(api, match.first.id!));
        total.images++;
      }
      lastError = null;
      return total;
    } catch (e) {
      lastError = '$e';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<List<drive.File>> _list(drive.DriveApi api) async {
    final out = <drive.File>[];
    String? token;
    do {
      final res = await api.files.list(
        spaces: 'appDataFolder',
        $fields: 'nextPageToken, files(id, name, modifiedTime, size)',
        pageSize: 1000,
        pageToken: token,
      );
      out.addAll(res.files ?? []);
      token = res.nextPageToken;
    } while (token != null);
    return out;
  }

  Future<void> _upload(drive.DriveApi api, String name, List<int> bytes, String? existingId) async {
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length);
    if (existingId == null) {
      final meta = drive.File()
        ..name = name
        ..parents = ['appDataFolder'];
      await api.files.create(meta, uploadMedia: media);
    } else {
      await api.files.update(drive.File(), existingId, uploadMedia: media);
    }
  }

  Future<List<int>> _download(drive.DriveApi api, String id) async {
    final media = await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final out = <int>[];
    await for (final chunk in media.stream) {
      out.addAll(chunk);
    }
    return out;
  }
}

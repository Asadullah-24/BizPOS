import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../services/backup_service.dart';
import '../../services/drive_service.dart';
import '../common.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  bool _images = true;

  Future<void> _run(Future<void> Function() fn, {String? success}) async {
    setState(() => _busy = true);
    await guard(context, fn, success: success);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _export() => _run(() async {
        final f = await BackupService.exportFile(includeImages: _images);
        await Share.shareXFiles([XFile(f.path)], subject: 'BizPOS backup', text: 'BizPOS backup ${Fmt.dateTime(DateTime.now().millisecondsSinceEpoch)}');
      });

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(title: Text(tr('How should this backup be restored?')), children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'merge'),
          child: ListTile(
            leading: const Icon(Icons.merge_type),
            title: Text(tr('Merge (recommended)')),
            subtitle: Text(tr('Adds everything from the backup. Nothing on this phone is lost.')),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'replace'),
          child: ListTile(
            leading: const Icon(Icons.restore_page_outlined, color: Colors.red),
            title: Text(tr('Replace')),
            subtitle: Text(tr('Deletes all data on this phone, then restores the backup.')),
          ),
        ),
      ]),
    );
    if (mode == null || !mounted) return;
    if (mode == 'replace' &&
        !await confirm(context, 'Replace all data', 'Everything on this phone will be deleted and replaced by the backup.', danger: true)) {
      return;
    }
    await _run(() async {
      final r = await BackupService.importFile(File(path), replace: mode == 'replace');
      if (mounted) showSnack(context, '${tr('Restored')}: $r');
      if (mode == 'replace') AppState.instance.lock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final drive = context.watch<DriveService>();
    final busy = _busy || drive.busy;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Backup & restore'))),
      body: AbsorbPointer(
        absorbing: busy,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (busy) const LinearProgressIndicator(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.add_to_drive, size: 32),
                  const SizedBox(width: 12),
                  Expanded(child: Text(tr('Google Drive backup'), style: Theme.of(context).textTheme.titleMedium)),
                ]),
                const SizedBox(height: 8),
                if (!drive.enabled) ...[
                  Text(tr('Backs up automatically whenever the phone is online. Stored privately in your Google Drive.')),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _run(() async {
                      if (!await drive.signIn()) throw StateError(drive.lastError ?? 'Google sign-in was cancelled.');
                      await drive.backupNow(interactive: true);
                    }, success: 'Google Drive backup is on'),
                    icon: const Icon(Icons.login),
                    label: Text(tr('Connect Google account')),
                  ),
                ] else ...[
                  Text('${tr('Account')}: ${drive.email ?? ''}'),
                  Text(drive.lastBackupAt == 0
                      ? tr('Not backed up yet')
                      : '${tr('Last backup')}: ${Fmt.dateTime(drive.lastBackupAt)}'),
                  Text(drive.hasPendingChanges ? tr('Changes waiting for internet') : tr('Everything is backed up')),
                  if (drive.lastError != null)
                    Text(drive.lastError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _run(() => drive.backupNow(interactive: true), success: 'Backup complete'),
                    icon: const Icon(Icons.cloud_upload),
                    label: Text(tr('Back up now')),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _run(() async {
                      final r = await drive.restoreAndMerge();
                      if (mounted) showSnack(context, '${tr('Synced')}: $r');
                    }),
                    icon: const Icon(Icons.sync),
                    label: Text(tr('Restore / sync from Drive')),
                  ),
                  TextButton(onPressed: () => drive.signOut(), child: Text(tr('Disconnect'))),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.save_alt, size: 32),
                  const SizedBox(width: 12),
                  Expanded(child: Text(tr('Backup file'), style: Theme.of(context).textTheme.titleMedium)),
                ]),
                const SizedBox(height: 8),
                Text(tr('Save a backup file to WhatsApp, email, USB or any app. Import it on any phone.')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Include product photos')),
                  value: _images,
                  onChanged: (v) => setState(() => _images = v),
                ),
                FilledButton.icon(onPressed: _export, icon: const Icon(Icons.ios_share), label: Text(tr('Export backup'))),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.file_open), label: Text(tr('Import backup'))),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              tr('Restoring never overwrites transactions. Every sale, payment and stock change has its own id, '
                  'so records from different phones are all kept. When the same product or customer was edited on two phones, '
                  'the newest edit wins. Stock and balances are recalculated after every restore.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ]),
      ),
    );
  }
}

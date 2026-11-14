import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../services/cloud_service.dart';
import '../services/update_service.dart';
import 'tokens.dart';

/// Shown above every screen, sign-in and lock screen included:
/// a full page when this version must be updated, a card when an update is available.
class UpdateGate extends StatelessWidget {
  const UpdateGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([UpdateService.instance, CloudService.instance]),
      builder: (context, _) {
        final u = UpdateService.instance;
        if (u.mustUpdate) return const _UpdatePage(force: true);
        if (u.canUpdate) return const _UpdatePage(force: false);
        return const SizedBox.shrink();
      },
    );
  }
}

class _UpdatePage extends StatefulWidget {
  const _UpdatePage({required this.force});
  final bool force;

  @override
  State<_UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<_UpdatePage> {
  bool _busy = false;

  Future<void> _update() async {
    setState(() => _busy = true);
    try {
      await UpdateService.instance.update();
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final u = UpdateService.instance;
    final theme = Theme.of(context);
    final card = Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(Tw.r2xl),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(gradient: Tw.brandGradient, borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 16),
        Text(
          tr(widget.force ? 'Please update BizPOS' : 'New update available'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          widget.force
              ? tr('This version is no longer supported. Update to keep using BizPOS. Your data stays safe on this phone.')
              : tr('A newer version of BizPOS is ready with new features and fixes.'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (u.message.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Tw.rXl),
            ),
            child: Text(u.message),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '${tr('Your version')}: ${u.version}${u.latest.isNotEmpty ? '  →  ${u.latest}' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _busy ? null : _update,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download_rounded),
            label: Text(tr('Update now')),
          ),
        ),
        if (!widget.force) ...[
          const SizedBox(height: 6),
          TextButton(onPressed: u.later, child: Text(tr('Later'))),
        ],
      ]),
    );
    return Material(
      color: widget.force ? theme.colorScheme.surfaceContainerLowest : Colors.black54,
      child: SafeArea(child: Center(child: SingleChildScrollView(child: card))),
    );
  }
}

/// Super admin: which version is the latest and which is the oldest allowed.
Future<void> appUpdatesDialog(BuildContext context) async {
  final s = CloudService.instance.appSettings;
  final u = UpdateService.instance;
  final latest = TextEditingController(text: '${s['latestVersion'] ?? ''}');
  final minimum = TextEditingController(text: '${s['minVersion'] ?? ''}');
  final message = TextEditingController(text: '${s['updateMessage'] ?? ''}');
  final apk = TextEditingController(text: '${s['apkUrl'] ?? ''}');
  final ios = TextEditingController(text: '${s['appStoreUrl'] ?? ''}');
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('App updates')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${tr('This phone')}: ${u.version.isEmpty ? '-' : '${u.version} (${u.build})'}',
              style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: latest,
            decoration: InputDecoration(
              labelText: tr('Latest version'),
              hintText: '1.3.0',
              helperText: tr('Older phones see "Update available" with a Later button.'),
              helperMaxLines: 2,
              suffixIcon: u.version.isEmpty
                  ? null
                  : IconButton(
                      tooltip: tr('Use this phone\'s version'),
                      icon: const Icon(Icons.phone_android_rounded),
                      onPressed: () => latest.text = u.version,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: minimum,
            decoration: InputDecoration(
              labelText: tr('Minimum version (must update)'),
              hintText: tr('Leave empty to never force'),
              helperText: tr('Phones below this cannot use the app until they update.'),
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(controller: message, maxLines: 3, decoration: InputDecoration(labelText: tr("What's new"))),
          const SizedBox(height: 8),
          TextField(
            controller: apk,
            decoration: InputDecoration(labelText: tr('APK download link (optional)'), hintText: UpdateService.defaultApkUrl),
          ),
          const SizedBox(height: 8),
          TextField(controller: ios, decoration: InputDecoration(labelText: tr('App Store link (optional)'))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
        FilledButton(
          onPressed: () async {
            final ok = RegExp(r'^\d+(\.\d+){0,2}$');
            for (final c in [latest, minimum]) {
              if (c.text.trim().isNotEmpty && !ok.hasMatch(c.text.trim())) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(tr('Write versions like 1.3.0'))));
                return;
              }
            }
            if (minimum.text.trim().isNotEmpty && latest.text.trim().isNotEmpty &&
                UpdateService.compare(minimum.text.trim(), latest.text.trim()) > 0) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(tr('Minimum cannot be higher than latest'))));
              return;
            }
            try {
              await FirebaseFirestore.instance.doc('settings/app').set({
                'latestVersion': latest.text.trim(),
                'minVersion': minimum.text.trim(),
                'updateMessage': message.text.trim(),
                'apkUrl': apk.text.trim(),
                'appStoreUrl': ios.text.trim(),
              }, SetOptions(merge: true));
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
            }
          },
          child: Text(tr('Save')),
        ),
      ],
    ),
  );
}

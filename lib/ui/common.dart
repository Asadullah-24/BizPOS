import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/db.dart';
import '../core/format.dart';
import '../core/i18n.dart';
import '../models/models.dart';
import '../services/ledger_service.dart';
import '../services/product_service.dart';

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 840;

void showSnack(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    behavior: SnackBarBehavior.floating,
  ));
}

String errorText(Object e) {
  if (e is StateError) return e.message;
  if (e is FormatException) return e.message;
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

/// Runs [fn], shows any error as a snackbar. Returns true on success.
Future<bool> guard(BuildContext context, Future<void> Function() fn, {String? success}) async {
  try {
    await fn();
    if (success != null && context.mounted) showSnack(context, tr(success));
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, tr(errorText(e)), error: true);
    return false;
  }
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Yes', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(title)),
      content: Text(tr(message)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr(ok)),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context, String title, {String initial = '', String? label, bool number = false}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(title)),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        decoration: InputDecoration(labelText: label == null ? null : tr(label)),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('OK'))),
      ],
    ),
  );
}

Future<DateTime?> pickDate(BuildContext context, DateTime initial) => showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

final List<TextInputFormatter> decimalInput = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))];

class NumField extends StatelessWidget {
  const NumField({super.key, required this.controller, required this.label, this.onChanged, this.autofocus = false, this.enabled = true, this.suffix});
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;
  final String? suffix;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        autofocus: autofocus,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: decimalInput,
        decoration: InputDecoration(labelText: tr(label), suffixText: suffix),
        onChanged: onChanged,
      );
}

String numText(double v) => v == 0 ? '' : Fmt.qty(v);

/// Rebuilds whenever the database changes or [deps] change.
class LiveData<T> extends StatefulWidget {
  const LiveData({super.key, required this.load, required this.builder, this.deps = const []});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final List<Object?> deps;

  @override
  State<LiveData<T>> createState() => _LiveDataState<T>();
}

class _LiveDataState<T> extends State<LiveData<T>> {
  T? _data;
  Object? _error;
  bool _loaded = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    Db.instance.changes.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(covariant LiveData<T> old) {
    super.didUpdateWidget(old);
    if (old.deps.length != widget.deps.length) {
      _reload();
      return;
    }
    for (var i = 0; i < widget.deps.length; i++) {
      if (old.deps[i] != widget.deps[i]) {
        _reload();
        return;
      }
    }
  }

  @override
  void dispose() {
    Db.instance.changes.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final t = ++_token;
    try {
      final d = await widget.load();
      if (!mounted || t != _token) return;
      setState(() {
        _data = d;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted || t != _token) return;
      setState(() {
        _error = e;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(errorText(_error!))));
    }
    return widget.builder(context, _data as T);
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(tr(text), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Search', this.trailing, this.controller, this.onSubmitted});
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hint;
  final Widget? trailing;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: tr(hint),
            suffixIcon: trailing,
            isDense: true,
          ),
        ),
      );
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.color, this.onTap, this.sub});
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = color ?? cs.primary;
    final dark = theme.brightness == Brightness.dark;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.withOpacity(dark ? 0.16 : 0.10), c.withOpacity(0.0)],
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.withOpacity(dark ? 0.22 : 0.14), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 19, color: c),
              ),
              const Spacer(),
              if (onTap != null) Icon(Icons.arrow_outward_rounded, size: 16, color: cs.onSurfaceVariant),
            ]),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            ),
            const SizedBox(height: 2),
            Text(
              sub == null ? tr(label) : '${tr(label)} · $sub',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Row(children: [
          Expanded(child: Text(tr(text), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2))),
          if (trailing != null) trailing!,
        ]),
      );
}

class KeyValue extends StatelessWidget {
  const KeyValue(this.label, this.value, {super.key, this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.normal, color: color, fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(tr(label), style: style)),
        Text(value, style: style),
      ]),
    );
  }
}

class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, required this.image, this.size = 44, this.name = ''});
  final String? image;
  final double size;
  final String name;

  @override
  Widget build(BuildContext context) {
    const palettes = [
      [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      [Color(0xFF0EA5E9), Color(0xFF6366F1)],
      [Color(0xFF10B981), Color(0xFF0EA5E9)],
      [Color(0xFFF59E0B), Color(0xFFF43F5E)],
      [Color(0xFFEC4899), Color(0xFF8B5CF6)],
      [Color(0xFF14B8A6), Color(0xFF22C55E)],
      [Color(0xFFF97316), Color(0xFFEAB308)],
    ];
    final hash = name.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0x7fffffff);
    final colors = palettes[hash % palettes.length];
    final all = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final lettered = all.where((w) => RegExp(r'^\p{L}', unicode: true).hasMatch(w)).toList();
    final words = lettered.isEmpty ? all : lettered;
    final initials = words.isEmpty
        ? '?'
        : (words.length == 1 ? words.first.characters.first : words[0].characters.first + words[1].characters.first).toUpperCase();
    final radius = size > 80 ? 16.0 : 10.0;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [colors[0].withOpacity(0.9), colors[1].withOpacity(0.75)]),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        initials,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: (size / 3).clamp(12, 44).toDouble(), letterSpacing: -0.5),
      ),
    );
    if (image == null || image!.isEmpty) return fallback;
    return FutureBuilder<File?>(
      future: ImageStore.file(image),
      builder: (ctx, snap) {
        final f = snap.data;
        if (f == null) return fallback;
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.file(f, width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).round()),
        );
      },
    );
  }
}

/// Account selector used by checkout, expenses, purchases and payments.
class AccountPicker extends StatelessWidget {
  const AccountPicker({super.key, required this.value, required this.onChanged, this.label = 'Account'});
  final String? value;
  final ValueChanged<Account?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => LiveData<List<Account>>(
        load: LedgerService.accounts,
        builder: (ctx, accounts) {
          final selected = accounts.any((a) => a.id == value) ? value : null;
          return DropdownButtonFormField<String>(
            value: selected,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr(label)),
            items: [
              for (final a in accounts)
                DropdownMenuItem(value: a.id, child: Text('${a.name}  (${Fmt.money(a.balance)})', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (id) => onChanged(accounts.where((a) => a.id == id).firstOrNull),
          );
        },
      );
}

IconData accountIcon(String type) => switch (type) {
      'bank' => Icons.account_balance,
      'digital' => Icons.phone_android,
      _ => Icons.payments,
    };

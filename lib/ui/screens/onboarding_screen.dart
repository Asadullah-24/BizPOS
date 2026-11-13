import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/business_templates.dart';
import '../../core/i18n.dart';
import '../../core/license.dart';
import '../../services/auth_service.dart';
import '../../services/backup_service.dart';
import '../../services/drive_service.dart';
import '../../services/setup_service.dart';
import '../common.dart';
import '../icons.dart';

const currencyPresets = <String, (String, int)>{
  'Pakistani Rupee (Rs)': ('Rs', 0),
  'Indian Rupee (₹)': ('₹', 2),
  'UAE Dirham (AED)': ('AED', 2),
  'Saudi Riyal (SAR)': ('SAR', 2),
  'US Dollar (\$)': ('\$', 2),
  'British Pound (£)': ('£', 2),
  'Euro (€)': ('€', 2),
  'Bangladeshi Taka (৳)': ('৳', 2),
};

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _busy = false;
  final _business = TextEditingController();
  final _symbol = TextEditingController(text: 'Rs');
  final _decimals = TextEditingController(text: '0');
  final _customType = TextEditingController();
  final _owner = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  BusinessTemplate _template = businessTemplates.first;
  String _lang = 'en';

  @override
  void initState() {
    super.initState();
    _business.text = LicenseService.instance.storeName ?? '';
  }

  Future<void> _setLang(String l) async {
    setState(() => _lang = l);
    AppState.instance.previewLanguage(l);
  }

  void _next() {
    if (_step == 0) {
      if (_business.text.trim().isEmpty) return showSnack(context, tr('Enter your business name.'), error: true);
      if (_symbol.text.trim().isEmpty) return showSnack(context, tr('Enter a currency symbol.'), error: true);
    }
    if (_step == 1 && _template.key == 'custom' && _customType.text.trim().isEmpty) {
      return showSnack(context, tr('Name your business type.'), error: true);
    }
    setState(() => _step++);
  }

  Future<void> _finish() async {
    if (_owner.text.trim().isEmpty) return showSnack(context, tr('Enter your name.'), error: true);
    final pin = _pin.text.trim();
    if (pin.length < 4 || int.tryParse(pin) == null) {
      return showSnack(context, tr('PIN must be at least 4 digits.'), error: true);
    }
    if (pin != _pin2.text.trim()) return showSnack(context, tr('PINs do not match.'), error: true);
    setState(() => _busy = true);
    await guard(context, () async {
      await SetupService.createBusiness(
        businessName: _business.text,
        template: _template,
        customTypeName: _template.key == 'custom' ? _customType.text : null,
        currencySymbol: _symbol.text,
        decimals: int.tryParse(_decimals.text) ?? 0,
        ownerName: _owner.text,
        pin: pin,
        language: _lang,
      );
      // Sign the owner in straight away.
      final owner = await AuthService.login(pin);
      if (owner != null) {
        await AppState.instance.login(owner);
        DriveService.instance.start();
      }
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restoreFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    await guard(context, () async {
      final r = await BackupService.importFile(File(path), replace: true);
      if (!AppState.instance.onboarded) throw StateError('The backup did not contain a business.');
      debugPrint('Restored: $r');
    }, success: 'Backup restored. Sign in with your PIN.');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restoreDrive() async {
    setState(() => _busy = true);
    await guard(context, () async {
      if (!await DriveService.instance.signIn()) throw StateError('Google sign-in was cancelled or failed.');
      await DriveService.instance.restoreAndMerge();
      if (!AppState.instance.onboarded) throw StateError('No business found in this Google account backup.');
    }, success: 'Backup restored. Sign in with your PIN.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final steps = [_basics(), _types(), _ownerStep()];
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Set up your business')),
        leading: _step > 0 ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _step--)) : null,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(children: [
              LinearProgressIndicator(value: _busy ? null : (_step + 1) / steps.length),
              Expanded(child: steps[_step]),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : (_step == steps.length - 1 ? _finish : _next),
                    child: Text(tr(_step == steps.length - 1 ? 'Start selling' : 'Next')),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _basics() => ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('Welcome to BizPOS'), style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(tr('Works fully offline. Your data stays on this phone and can be backed up to Google Drive.')),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          value: _lang,
          decoration: InputDecoration(labelText: tr('Language')),
          items: [for (final e in I18n.languages.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => _setLang(v ?? 'en'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _business, decoration: InputDecoration(labelText: tr('Business name'))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: tr('Currency')),
          value: currencyPresets.keys.first,
          isExpanded: true,
          items: [for (final k in currencyPresets.keys) DropdownMenuItem(value: k, child: Text(k))],
          onChanged: (k) {
            final c = currencyPresets[k];
            if (c == null) return;
            _symbol.text = c.$1;
            _decimals.text = '${c.$2}';
          },
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _symbol, decoration: InputDecoration(labelText: tr('Currency symbol')))),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _decimals,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Decimal places')),
            ),
          ),
        ]),
        const SizedBox(height: 28),
        Text(tr('Moving from another phone?'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _restoreDrive,
          icon: const Icon(Icons.cloud_download_outlined),
          label: Text(tr('Restore from Google Drive')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _restoreFile,
          icon: const Icon(Icons.file_open_outlined),
          label: Text(tr('Restore from a backup file')),
        ),
      ]);

  Widget _types() {
    final cols = MediaQuery.sizeOf(context).width > 600 ? 3 : 2;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(tr('What kind of business is it?'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(tr('This sets up categories, units, product fields and modules. You can change everything later.')),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.5,
        children: [
          for (final t in businessTemplates)
            _TypeCard(
              template: t,
              selected: t.key == _template.key,
              onTap: () => setState(() => _template = t),
            ),
        ],
      ),
      if (_template.key == 'custom') ...[
        const SizedBox(height: 16),
        TextField(
          controller: _customType,
          decoration: InputDecoration(labelText: tr('Business type name'), hintText: tr('e.g. Bakery, Book shop')),
        ),
      ],
    ]);
  }

  Widget _ownerStep() => ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('Owner account'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(tr('The PIN unlocks the app. Employees get their own PINs later.')),
        const SizedBox(height: 16),
        TextField(controller: _owner, decoration: InputDecoration(labelText: tr('Your name'))),
        const SizedBox(height: 12),
        TextField(
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: InputDecoration(labelText: tr('PIN (4-8 digits)')),
        ),
        TextField(
          controller: _pin2,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: InputDecoration(labelText: tr('Confirm PIN')),
        ),
      ]);
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.template, required this.selected, required this.onTap});
  final BusinessTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest.withOpacity(0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? cs.primary : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(businessIcon(template.icon), size: 32, color: selected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(tr(template.name), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

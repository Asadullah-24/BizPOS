import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/license.dart';
import '../../core/packages.dart';
import '../../core/permissions.dart';
import '../../models/models.dart';
import '../../services/inventory_service.dart';
import '../../services/product_service.dart';
import '../../services/voice_service.dart';
import '../common.dart';
import 'plan_screen.dart';

/// Update stock by speaking: "sugar 10 kg add", "remove 2 milk", "rice 25 set".
/// Pro plan: unlimited. Otherwise each applied command uses one credit.
class VoiceStockScreen extends StatefulWidget {
  const VoiceStockScreen({super.key});

  @override
  State<VoiceStockScreen> createState() => _VoiceStockScreenState();
}

class _VoiceStockScreenState extends State<VoiceStockScreen> {
  final _rec = VoiceRecognizer();
  String _heard = '';
  bool _listening = false;
  VoiceCommand? _cmd;
  String? _error;
  String _locale = 'en_US';
  final List<String> _log = [];
  List<Product> _products = [];

  @override
  void initState() {
    super.initState();
    ProductService.sellable().then((p) => _products = p);
  }

  @override
  void dispose() {
    _rec.stop();
    super.dispose();
  }

  Future<void> _listen() async {
    final lic = LicenseService.instance;
    if (!lic.has(Feature.voice) && lic.credits < Credits.voiceCost) {
      setState(() => _error = tr('No credits left. Watch an ad or buy credits.'));
      return;
    }
    setState(() {
      _heard = '';
      _cmd = null;
      _error = null;
      _listening = true;
    });
    _products = await ProductService.sellable();
    try {
      await _rec.listen(
        localeId: _locale,
        onText: (text, isFinal) {
          if (!mounted) return;
          setState(() => _heard = text);
          if (isFinal) _parse(text);
        },
      );
      // Stop waiting once the recognizer times out without a final result.
      Future<void>.delayed(const Duration(seconds: 14), () {
        if (mounted && _listening) _parse(_heard);
      });
    } catch (e) {
      setState(() {
        _listening = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _stop() async {
    await _rec.stop();
    // Some phones do not send a final result after a manual stop.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted && _listening) _parse(_heard);
  }

  void _parse(String text) {
    final cmd = VoiceParser.parse(text, _products);
    setState(() {
      _listening = false;
      _cmd = cmd;
      _error = cmd == null ? tr('Could not match a product. Say the product name and quantity, e.g. "sugar 10 kg add".') : null;
    });
  }

  Future<void> _apply() async {
    final c = _cmd;
    if (c == null) return;
    final lic = LicenseService.instance;
    final ok = await guard(context, () async {
      if (!lic.has(Feature.voice)) await lic.spend(Credits.voiceCost.toDouble(), 'Voice stock update');
      await InventoryService.adjust(
        productId: c.product.id,
        mode: c.action,
        qty: c.qty,
        note: 'Voice: ${c.heard}',
        employeeId: AppState.instance.user?.id,
      );
    });
    if (!ok || !mounted) return;
    final fresh = await ProductService.byId(c.product.id);
    setState(() {
      _log.insert(0, '${_actionLabel(c.action)} ${Fmt.qty(c.qty)} · ${c.product.displayName} → ${Fmt.qty(fresh?.stock ?? 0)} ${c.product.unit ?? ''}');
      _cmd = null;
      _heard = '';
    });
  }

  String _actionLabel(String a) => tr(switch (a) { 'remove' => 'Removed', 'set' => 'Set to', _ => 'Added' });

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseService>();
    final cs = Theme.of(context).colorScheme;
    final canAdjust = AppState.instance.can(Perm.inventory);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Voice stock update')), actions: [
        TextButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen())),
          icon: const Icon(Icons.toll),
          label: Text(lic.has(Feature.voice) ? tr('Unlimited') : '${Fmt.qty(lic.credits)} ${tr('credits')}'),
        ),
      ]),
      body: !canAdjust
          ? const EmptyState(icon: Icons.lock, text: 'You do not have permission to adjust stock.')
          : ListView(padding: const EdgeInsets.all(16), children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'en_US', label: Text('English')),
                  ButtonSegment(value: 'ur_PK', label: Text('اردو')),
                ],
                selected: {_locale},
                onSelectionChanged: (s) => setState(() => _locale = s.first),
              ),
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: _listening ? _stop : _listen,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: _listening ? 150 : 130,
                    height: _listening ? 150 : 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _listening ? Colors.red : cs.primary,
                      boxShadow: [BoxShadow(color: (_listening ? Colors.red : cs.primary).withOpacity(0.4), blurRadius: 30, spreadRadius: 4)],
                    ),
                    child: Icon(_listening ? Icons.stop : Icons.mic, color: Colors.white, size: 60),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tr(_listening ? 'Listening...' : 'Tap and say, for example: "sugar 10 kg add" or "remove 2 milk"'),
                textAlign: TextAlign.center,
              ),
              if (_heard.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('"$_heard"', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
                ),
              if (_cmd != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'add', label: Text(tr('Add'))),
                          ButtonSegment(value: 'remove', label: Text(tr('Remove'))),
                          ButtonSegment(value: 'set', label: Text(tr('Count'))),
                        ],
                        selected: {_cmd!.action},
                        onSelectionChanged: (s) => setState(() => _cmd = VoiceCommand(
                            action: s.first, qty: _cmd!.qty, product: _cmd!.product, heard: _cmd!.heard, alternatives: _cmd!.alternatives)),
                      ),
                      const SizedBox(height: 12),
                      Text('${Fmt.qty(_cmd!.qty)} ${_cmd!.product.unit ?? ''}',
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(_cmd!.product.displayName, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                      Text('${tr('Current stock')}: ${Fmt.qty(_cmd!.product.stock)}', textAlign: TextAlign.center),
                      if (_cmd!.alternatives.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(tr('Not this product?'), textAlign: TextAlign.center),
                        Wrap(alignment: WrapAlignment.center, spacing: 6, children: [
                          for (final p in _cmd!.alternatives)
                            ActionChip(
                              label: Text(p.displayName),
                              onPressed: () => setState(() => _cmd = VoiceCommand(
                                  action: _cmd!.action, qty: _cmd!.qty, product: p, heard: _cmd!.heard)),
                            ),
                        ]),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _apply,
                        icon: const Icon(Icons.check),
                        label: Text(lic.has(Feature.voice) ? tr('Update stock') : '${tr('Update stock')} (-${Credits.voiceCost} ${tr('credit')})'),
                      ),
                    ]),
                  ),
                ),
              ],
              if (_log.isNotEmpty) ...[
                const SectionTitle('Done'),
                for (final l in _log) ListTile(dense: true, leading: const Icon(Icons.check, color: Colors.green), title: Text(l)),
              ],
            ]),
    );
  }
}

import 'package:speech_to_text/speech_to_text.dart';

import '../models/models.dart';

class VoiceCommand {
  VoiceCommand({required this.action, required this.qty, required this.product, required this.heard, this.alternatives = const []});

  /// add | remove | set
  final String action;
  final double qty;
  final Product product;
  final String heard;
  final List<Product> alternatives;
}

/// Turns phrases like "sugar 10 kg add", "add 5 rice", "cheeni das kilo jama karo"
/// or "remove 2 milk" into a stock change. Pure Dart so it can be tested.
class VoiceParser {
  static const _add = {
    'add', 'added', 'plus', 'increase', 'receive', 'received', 'jama', 'daal', 'dal', 'dalo', 'daalo', 'dalein',
    'barhao', 'badhao', 'aaya', 'aya', 'aayi', 'shamil', 'شامل', 'جمع', 'ڈالو', 'ڈال',
  };
  static const _remove = {
    'remove', 'removed', 'minus', 'less', 'reduce', 'decrease', 'sold', 'sell', 'kam', 'nikal', 'nikalo', 'nikaalo',
    'becha', 'bika', 'kharab', 'damaged', 'کم', 'نکالو', 'نکال',
  };
  static const _set = {'set', 'count', 'total', 'equal', 'baraabar', 'barabar'};
  static const _units = {
    'kg', 'kgs', 'kilo', 'kilos', 'kilogram', 'kilograms', 'g', 'gm', 'gram', 'grams', 'ltr', 'liter', 'litre', 'liters',
    'litres', 'ml', 'pcs', 'pc', 'piece', 'pieces', 'packet', 'packets', 'pack', 'packs', 'box', 'boxes', 'dozen',
    'bottle', 'bottles', 'bag', 'bags', 'unit', 'units', 'meter', 'meters', 'ft', 'strip', 'strips', 'tube', 'tubes',
    'carton', 'cartons', 'کلو', 'کلوگرام', 'لیٹر', 'پیس',
  };
  static const _filler = {
    'karo', 'kardo', 'kar', 'do', 'please', 'to', 'of', 'the', 'stock', 'in', 'into', 'from', 'ki', 'ka', 'ke', 'me', 'mein',
    'main', 'and', 'aur', 'hai', 'hain', 'is', 'my', 'kr', 'krdo', 'kro', 'dain', 'den', 'دو', 'کرو', 'میں', 'کا', 'کی',
  };
  static const Map<String, double> _numbers = {
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
    'ten': 10, 'eleven': 11, 'twelve': 12, 'fifteen': 15, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
    'hundred': 100, 'half': 0.5, 'ek': 1, 'aik': 1, 'teen': 3, 'char': 4, 'chaar': 4, 'panch': 5, 'paanch': 5,
    'chay': 6, 'chhe': 6, 'chhay': 6, 'saat': 7, 'aath': 8, 'nau': 9, 'das': 10, 'gyarah': 11, 'barah': 12,
    'pandrah': 15, 'bees': 20, 'tees': 30, 'chalees': 40, 'pachas': 50, 'sau': 100, 'aadha': 0.5, 'adha': 0.5,
    'ایک': 1, 'دو': 2, 'تین': 3, 'چار': 4, 'پانچ': 5, 'دس': 10, 'بیس': 20, 'سو': 100,
  };

  static String _normalizeDigits(String s) {
    const urdu = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final u = urdu.indexOf(ch);
      final a = arabic.indexOf(ch);
      b.write(u >= 0 ? '$u' : (a >= 0 ? '$a' : ch));
    }
    return b.toString();
  }

  static List<String> tokens(String text) {
    var t = _normalizeDigits(text.toLowerCase());
    // "10kg" -> "10 kg", "kg10" -> "kg 10"
    t = t.replaceAllMapped(RegExp(r'(\d)([^\d\s.,])'), (m) => '${m[1]} ${m[2]}');
    t = t.replaceAllMapped(RegExp(r'([^\d\s.,])(\d)'), (m) => '${m[1]} ${m[2]}');
    t = t.replaceAll(RegExp(r'[^\p{L}\p{N}.]+', unicode: true), ' ');
    return t.split(' ').map((e) => e.replaceAll(RegExp(r'^\.+|\.+$'), '')).where((e) => e.isNotEmpty).toList();
  }

  static int _distance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  static bool _wordMatch(String q, String w) {
    if (q == w) return true;
    if (q.length >= 3 && (w.startsWith(q) || q.startsWith(w) && w.length >= 3)) return true;
    if (q.length >= 4 && w.length >= 4 && _distance(q, w) <= 1) return true;
    return false;
  }

  /// Returns null when no action/product could be understood.
  static VoiceCommand? parse(String heard, List<Product> products) {
    final toks = tokens(heard);
    if (toks.isEmpty) return null;
    String? action;
    double? qty;
    final rest = <String>[];
    for (var i = 0; i < toks.length; i++) {
      final t = toks[i];
      if (_add.contains(t)) {
        action ??= 'add';
        continue;
      }
      if (_remove.contains(t)) {
        action ??= 'remove';
        continue;
      }
      if (_set.contains(t)) {
        action ??= 'set';
        continue;
      }
      final n = double.tryParse(t) ?? _numbers[t];
      if (n != null && !(t == 'do' && qty != null)) {
        if ((t == 'hundred' || t == 'sau') && qty != null) {
          qty = qty * 100;
        } else {
          qty ??= n;
        }
        continue;
      }
      if (_units.contains(t) || _filler.contains(t)) continue;
      rest.add(t);
    }
    if (rest.isEmpty) return null;

    final scored = <(Product, double)>[];
    final phrase = rest.join(' ');
    for (final p in products) {
      final words = tokens(p.displayName).where((w) => !_units.contains(w)).toList();
      if (words.isEmpty) continue;
      var hits = 0;
      for (final q in rest) {
        if (words.any((w) => _wordMatch(q, w))) hits++;
      }
      var score = hits / rest.length;
      final name = p.displayName.toLowerCase();
      if (name == phrase) score += 1;
      if (name.contains(phrase)) score += 0.3;
      // Prefer shorter names when equally matched ("rice" over "rice flour").
      score -= words.length * 0.01;
      if (score >= 0.5) scored.add((p, score));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return VoiceCommand(
      action: action ?? 'add',
      qty: qty ?? 1,
      product: scored.first.$1,
      heard: heard,
      alternatives: scored.skip(1).take(3).map((e) => e.$1).toList(),
    );
  }
}

/// Wraps the phone's speech recognizer. On Android it works offline when the
/// offline speech pack for the language is installed in Google settings.
class VoiceRecognizer {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  String? lastError;

  Future<bool> init() async {
    if (_ready) return true;
    _ready = await _stt.initialize(onError: (e) => lastError = e.errorMsg);
    return _ready;
  }

  bool get listening => _stt.isListening;

  Future<void> listen({required String localeId, required void Function(String text, bool isFinal) onText}) async {
    if (!await init()) throw StateError('Speech recognition is not available on this phone.');
    await _stt.listen(
      onResult: (r) => onText(r.recognizedWords, r.finalResult),
      localeId: localeId,
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> stop() => _stt.stop();
}

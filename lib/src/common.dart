/// Finans araçlarının ortak yardımcıları (arac-motoru'ndan kopyalanıp
/// sadeleştirildi): çeviri, liste düzeni, seçim alanları, tutar alanı,
/// para simgesi, CSV dışa aktarma ve silme onayı.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:studio_core/apps/apps.dart';

import 'core.dart';
import 'platform/export.dart';
import 'tx.dart';

/// Araç etiketi (33 dil).
String L(ToolContext t, String key) => t.t(kFinL[key] ?? [key]);

/// Virgülle ayrılmış etiket listesi.
List<String> Ls(ToolContext t, String key) => L(t, key).split(',');

/// Aracın gövdesi: kaydırılabilir sütun.
class ToolList extends StatelessWidget {
  final List<Widget> children;
  const ToolList({super.key, required this.children});

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.only(top: 8, bottom: 32), children: children);
}

/// "Bu cihazda yok" bilgisi.
Widget notAvailable(ToolContext t) =>
    AppInfoCard(t.tx(kIsWeb ? 'web_unavailable' : 'not_available'), icon: Icons.sensors_off_rounded);

/// Büyük sayı göstergesi.
class BigReadout extends StatelessWidget {
  final String value;
  final String unit;
  final String? caption;
  const BigReadout(this.value, {super.key, this.unit = '', this.caption});

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    return AppPanel(
      child: Column(children: [
        if (caption != null) Text(caption!, style: const TextStyle(color: Colors.white70, fontSize: 15)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(value, style: TextStyle(color: s.number, fontSize: 64, fontWeight: FontWeight.w900)),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(unit, style: const TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Seçenek düğmeleri (SegmentedButton) için kısa yol.
class Choice<T> extends StatelessWidget {
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;
  const Choice({super.key, required this.values, required this.labels, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [
            for (var i = 0; i < values.length; i++) ButtonSegment<T>(value: values[i], label: Text(labels[i])),
          ],
          selected: {selected},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    );
  }
}

/// Açılır liste.
class Pick<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final String Function(T) text;
  final T value;
  final ValueChanged<T> onChanged;
  const Pick({
    super.key,
    required this.label,
    required this.values,
    required this.text,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        items: [for (final v in values) DropdownMenuItem<T>(value: v, child: Text(text(v), overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// Düz metin alanı.
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool obscure;
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.onChanged,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        obscureText: obscure,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 17),
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: maxLines > 1,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

/// Tarih seçme satırı.
class DateRow extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? first;
  final DateTime? last;
  const DateRow({super.key, required this.label, required this.value, required this.onChanged, this.first, this.last});

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_rounded),
      title: Text(label),
      subtitle: Text(loc.formatFullDate(value)),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: first ?? DateTime(1800),
          lastDate: last ?? DateTime(2300),
        );
        if (d != null) onChanged(d);
      },
    );
  }
}


// ------------------------------------------------------------ finans

/// Aracın para simgesi (kullanıcı değiştirebilir; varsayılan dile göre).
Future<String> loadCurrency(ToolContext t) async => await t.store.read('cur') ?? defaultCurrency(t.lang);

/// Para simgesini soran küçük pencere.
Future<String?> askCurrency(BuildContext context, ToolContext t, String current) async {
  final c = TextEditingController(text: current);
  final v = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(L(t, 'currency')),
      content: AppTextField(controller: c, label: L(t, 'currency')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(t.core('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: Text(t.core('ok'))),
      ],
    ),
  );
  c.dispose();
  if (v != null) await t.store.write('cur', v);
  return v;
}

/// CSV'yi panoya kopyalar; mobil/masaüstünde ayrıca dosyaya yazar.
Future<void> exportCsv(BuildContext context, ToolContext t, String name, String csv) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: csv));
  String? path;
  if (Exporter.supported) {
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    path = await Exporter.saveText('${name}_$stamp.csv', csv);
  }
  messenger?.showSnackBar(SnackBar(
    content: Text(path == null ? L(t, 'csv_copied') : '${L(t, 'csv_copied')}\n${L(t, 'csv_saved')} $path'),
  ));
}

/// Silme onayı.
Future<bool> confirmDelete(BuildContext context, ToolContext t) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(L(t, 'confirm_delete')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t.core('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(L(t, 'delete'))),
      ],
    ),
  );
  return ok == true;
}

/// Kayıt formunun bir alanı.
class F {
  final String key;
  final String label;
  final String kind; // text | money | date | choice | toggle | int
  final Object? initial;
  final List<String> options;
  final bool must;
  const F.text(this.key, this.label, {String this.initial = '', this.must = false})
      : kind = 'text',
        options = const [];
  const F.money(this.key, this.label, {int? this.initial, this.must = true})
      : kind = 'money',
        options = const [];
  const F.date(this.key, this.label, {DateTime? this.initial})
      : kind = 'date',
        options = const [],
        must = false;
  const F.choice(this.key, this.label, this.options, {int this.initial = 0})
      : kind = 'choice',
        must = false;
  const F.toggle(this.key, this.label, {bool this.initial = false})
      : kind = 'toggle',
        options = const [],
        must = false;
  const F.integer(this.key, this.label, {int this.initial = 1})
      : kind = 'int',
        options = const [],
        must = true;
}

/// Alanlardan oluşan kayıt penceresi. Değerler: text → String, money → int
/// (kuruş; boşsa null), date → DateTime, choice/int → int, toggle → bool.
Future<Map<String, Object?>?> editForm(BuildContext context, ToolContext t, String title, List<F> fields) {
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) => _FormDialog(t: t, title: title, fields: fields),
  );
}

class _FormDialog extends StatefulWidget {
  final ToolContext t;
  final String title;
  final List<F> fields;
  const _FormDialog({required this.t, required this.title, required this.fields});

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final Map<String, TextEditingController> _c = {};
  final Map<String, Object?> _v = {};
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      switch (f.kind) {
        case 'text':
          _c[f.key] = TextEditingController(text: f.initial as String? ?? '');
        case 'money':
          final i = f.initial as int?;
          _c[f.key] = TextEditingController(text: i == null ? '' : (i / 100).toStringAsFixed(2));
        case 'int':
          _c[f.key] = TextEditingController(text: '${f.initial ?? 1}');
        default:
          _v[f.key] = f.initial;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object?>? _collect() {
    final out = <String, Object?>{};
    for (final f in widget.fields) {
      switch (f.kind) {
        case 'text':
          final s = _c[f.key]!.text.trim();
          if (f.must && s.isEmpty) return null;
          out[f.key] = s;
        case 'money':
          final raw = _c[f.key]!.text;
          final v = parseCents(raw);
          if (v == null && (f.must || raw.trim().isNotEmpty)) return null;
          if (f.must && v == 0) return null;
          out[f.key] = v;
        case 'int':
          final v = int.tryParse(_c[f.key]!.text.trim());
          if (v == null) return null;
          out[f.key] = v;
        default:
          out[f.key] = _v[f.key];
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final f in widget.fields) _field(f),
            if (_tried) Padding(padding: const EdgeInsets.only(top: 8), child: Text(L(t, 'invalid'), style: const TextStyle(color: Colors.orangeAccent))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.core('cancel'))),
        FilledButton(
          onPressed: () {
            final r = _collect();
            if (r == null) {
              setState(() => _tried = true);
            } else {
              Navigator.pop(context, r);
            }
          },
          child: Text(L(t, 'save')),
        ),
      ],
    );
  }

  Widget _field(F f) {
    switch (f.kind) {
      case 'text':
        return AppTextField(controller: _c[f.key]!, label: f.label);
      case 'money':
      case 'int':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AppNumberField(controller: _c[f.key]!, label: f.label, decimal: f.kind == 'money'),
        );
      case 'date':
        final d = _v[f.key] as DateTime?;
        return Row(children: [
          Expanded(
            child: DateRow(
              label: f.label,
              value: d ?? DateTime.now(),
              onChanged: (x) => setState(() => _v[f.key] = x),
            ),
          ),
          if (d != null && f.initial == null)
            IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _v[f.key] = null)),
        ]);
      case 'choice':
        return Pick<int>(
          label: f.label,
          values: List.generate(f.options.length, (i) => i),
          text: (i) => f.options[i],
          value: (_v[f.key] as int? ?? 0).clamp(0, f.options.length - 1),
          onChanged: (i) => setState(() => _v[f.key] = i),
        );
      default:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _v[f.key] as bool? ?? false,
          onChanged: (b) => setState(() => _v[f.key] = b),
        );
    }
  }
}

/// Liste boşken gösterilen not.
Widget emptyNote(ToolContext t) => AppInfoCard(L(t, 'empty_list'), icon: Icons.inbox_rounded);

/// Kaynak ve güncelleme tarihi satırı.
Widget sourceNote(ToolContext t, String src, String date) =>
    AppInfoCard('${t.tx('source', {'src': src})} · ${t.tx('as_of', {'date': date})}', icon: Icons.fact_check_rounded);

/// Satır sonu araç çubuğu: para simgesi ve CSV.
class BookBar extends StatelessWidget {
  final ToolContext t;
  final String currency;
  final ValueChanged<String> onCurrency;
  final VoidCallback? onExport;
  final List<Widget> extra;
  const BookBar({super.key, required this.t, required this.currency, required this.onCurrency, this.onExport, this.extra = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.end, children: [
        ...extra,
        ActionChip(
          avatar: const Icon(Icons.currency_exchange_rounded, size: 18),
          label: Text(currency.isEmpty ? L(t, 'currency') : currency),
          onPressed: () async {
            final v = await askCurrency(context, t, currency);
            if (v != null) onCurrency(v);
          },
        ),
        if (onExport != null)
          ActionChip(avatar: const Icon(Icons.file_download_rounded, size: 18), label: Text(L(t, 'export_csv')), onPressed: onExport),
      ]),
    );
  }
}

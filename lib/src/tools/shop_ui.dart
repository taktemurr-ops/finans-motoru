/// 4. tur kayıt araçları: altın günü (dönüşümlü birikim grubu), esnaf
/// veresiye defteri, kişisel sepet enflasyonu, mini kasa ve stok.
///
/// Hiçbiri para tutmaz, taşımaz ya da ödeme almaz; yalnızca kayıt tutar.
/// Hatırlatma ve çizelge metinlerini kullanıcı paylaşım menüsünden kendisi
/// gönderir (uygulama kimseye mesaj göndermez).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:studio_core/apps/apps.dart';

import '../books.dart';
import '../common.dart';
import '../core.dart';
import '../shop.dart';
import 'books_ui.dart';
import '../fold.dart';

/// Metni sistem paylaşım menüsüyle paylaşır; olmazsa panoya kopyalar.
Future<void> shareText(BuildContext context, ToolContext t, String text) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await SharePlus.instance.share(ShareParams(text: text));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    messenger?.showSnackBar(SnackBar(content: Text(L(t, 'copied_text'))));
  }
}

/// Başlık satırı ve geri düğmesi (liste → ayrıntı).
Widget _backRow(BuildContext context, String title, VoidCallback onBack) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        IconButton(onPressed: onBack, icon: const BackButtonIcon(), tooltip: MaterialLocalizations.of(context).backButtonTooltip),
        Expanded(
          child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        ),
      ]),
    );

// ========================================================= altın günü

class RoscaTool extends StatefulWidget {
  final ToolContext t;
  const RoscaTool(this.t, {super.key});
  @override
  State<RoscaTool> createState() => _RoscaState();
}

class _RoscaState extends BookState<RoscaTool> {
  @override
  ToolContext get t => widget.t;
  List<Rosca> _g = [];
  String? _open;
  static const _freqs = ['month', '2week', 'week'];

  @override
  Future<void> load() async {
    _g = (await readList('groups')).map(Rosca.fromJson).whereType<Rosca>().toList();
  }

  void _set(List<Rosca> g) {
    setState(() => _g = g);
    unawaited(t.store.writeList('groups', [for (final x in g) x.toJson()]));
  }

  void _put(Rosca g) => _set([for (final x in _g) x.id == g.id ? g : x]);

  String _amt(Rosca g, int cents) => g.unit.isEmpty ? mc(cents) : '${fmtCents(cents, t.lang)} ${g.unit}';

  String _freqLabel(String f) => L(t, f == 'week' ? 'weekly' : f == '2week' ? 'ag_biweekly' : 'monthly');

  Future<void> _edit([Rosca? e]) async {
    final r = await editForm(context, t, L(t, e == null ? 'add' : 'edit'), [
      F.text('name', L(t, 'name'), initial: e?.name ?? '', must: true),
      F.money('amount', L(t, 'ag_share'), initial: e?.amount),
      F.text('unit', L(t, 'ag_unit'), initial: e?.unit ?? ''),
      F.choice('freq', L(t, 'period'), [L(t, 'monthly'), L(t, 'ag_biweekly'), L(t, 'weekly')],
          initial: e == null ? 0 : _freqs.indexOf(e.freq).clamp(0, 2)),
      F.date('start', L(t, 'ag_first'), initial: e?.start ?? DateTime.now()),
      F.text('members', L(t, 'ag_members'), initial: e?.members.join(', ') ?? '', must: true),
      F.text('note', L(t, 'note'), initial: e?.note ?? ''),
    ]);
    if (r == null || !mounted) return;
    final ms = [
      for (final m in (r['members'] as String).split(RegExp(r'[,\n،、，;]')))
        if (m.trim().isNotEmpty) m.trim(),
    ];
    if (ms.length < 2) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(L(t, 'ag_min_members'))));
      return;
    }
    final changedMembers = e != null && e.members.join('\n') != ms.join('\n');
    final g = Rosca(
      id: e?.id ?? newId(),
      name: r['name'] as String,
      amount: r['amount'] as int,
      unit: r['unit'] as String,
      freq: _freqs[r['freq'] as int],
      start: r['start'] as DateTime? ?? DateTime.now(),
      members: ms,
      note: r['note'] as String,
      // Üyeler değişirse eski işaretler yanlış kişiye düşmesin.
      paid: changedMembers ? const {} : e?.paid ?? const {},
      delivered: changedMembers ? const {} : e?.delivered ?? const {},
    );
    _set([for (final x in _g) if (x.id != g.id) x, g]);
    setState(() => _open = g.id);
  }

  Future<void> _draw(Rosca g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.shuffle_rounded, size: 40),
        title: Text(L(t, 'ag_draw')),
        content: Text(L(t, 'ag_draw_note')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(t.core('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(L(t, 'ag_draw'))),
        ],
      ),
    );
    if (ok == true) _put(g.shuffled(math.Random.secure()));
  }

  String _scheduleText(Rosca g) {
    final b = StringBuffer('${g.name}\n${L(t, 'ag_share')}: ${_amt(g, g.amount)} · ${L(t, 'ag_pot')}: ${_amt(g, g.pot)}\n');
    for (var i = 0; i < g.rounds; i++) {
      b.writeln('${i + 1}. ${date(g.dateOf(i))} — ${g.members[i]}${g.delivered.contains(i) ? ' ✓' : ''}');
    }
    b.write(L(t, 'ag_record_only'));
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    Rosca? open;
    for (final g in _g) {
      if (g.id == _open) open = g;
    }
    return open == null ? _list(context) : _detail(context, open);
  }

  String _summary(Rosca g, DateTime now) {
    final n = g.nextRound(now);
    return [
      '${g.members.length} ${L(t, 'ag_people')} · ${_freqLabel(g.freq)}',
      if (n != null) '${L(t, 'ag_next')}: ${date(g.dateOf(n))} — ${g.members[n]}',
      if (g.finished) L(t, 'ag_done'),
    ].join('\n');
  }

  Widget _memberLine(Rosca g, int m) {
    final tot = g.memberTotals(m);
    return line(g.members[m], '${L(t, 'paid')}: ${_amt(g, tot.$1)} · ${L(t, 'ag_received')}: ${_amt(g, tot.$2)}');
  }

  Widget _list(BuildContext context) {
    final now = DateTime.now();
    return ToolList(children: [
      bar(),
      AppInfoCard(L(t, 'ag_record_only'), icon: Icons.menu_book_rounded),
      AppButton(label: L(t, 'add'), icon: Icons.group_add_rounded, onPressed: () => _edit()),
      if (_g.isEmpty) emptyNote(t),
      for (final g in _g)
        Card(
          child: ListTile(
            leading: Icon(g.finished ? Icons.task_alt_rounded : Icons.diversity_3_rounded),
            title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(_summary(g, now)),
            trailing: Text(_amt(g, g.pot), style: const TextStyle(fontWeight: FontWeight.w800)),
            onTap: () => setState(() => _open = g.id),
          ),
        ),
    ]);
  }

  Widget _detail(BuildContext context, Rosca g) {
    final now = DateTime.now();
    final next = g.nextRound(now);
    final missing = g.missing(now);
    return ToolList(children: [
      _backRow(context, g.name, () => setState(() => _open = null)),
      AppPanel(
        child: Column(children: [
          line(L(t, 'ag_pot'), _amt(g, g.pot), big: true),
          line(L(t, 'ag_share'), '${_amt(g, g.amount)} · ${_freqLabel(g.freq)}'),
          if (next != null) line(L(t, 'ag_next'), '${date(g.dateOf(next))} — ${g.members[next]}'),
          line(L(t, 'ag_missing'), '${missing.length}'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          ActionChip(avatar: const Icon(Icons.edit_rounded, size: 18), label: Text(L(t, 'edit')), onPressed: () => _edit(g)),
          if (!g.started)
            ActionChip(avatar: const Icon(Icons.shuffle_rounded, size: 18), label: Text(L(t, 'ag_draw')), onPressed: () => _draw(g)),
          ActionChip(
            avatar: const Icon(Icons.share_rounded, size: 18),
            label: Text(L(t, 'ag_share_plan')),
            onPressed: () => shareText(context, t, _scheduleText(g)),
          ),
          ActionChip(
            avatar: const Icon(Icons.file_download_rounded, size: 18),
            label: Text(L(t, 'export_csv')),
            onPressed: () => exportCsv(context, t, 'group', roscaCsv(g)),
          ),
          ActionChip(
            avatar: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(L(t, 'delete')),
            onPressed: () async {
              if (await confirmDelete(context, t)) {
                _set([for (final x in _g) if (x.id != g.id) x]);
                setState(() => _open = null);
              }
            },
          ),
        ]),
      ),
      if (g.note.isNotEmpty) AppInfoCard(g.note, icon: Icons.sticky_note_2_rounded),
      AppHeading(L(t, 'ag_schedule'), icon: Icons.event_repeat_rounded),
      for (var i = 0; i < g.rounds; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(radius: 16, child: Text('${i + 1}')),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${g.members[i]}\n${date(g.dateOf(i))}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                Text(_amt(g, g.collected(i))),
              ]),
              const SizedBox(height: 8),
              Text(L(t, 'ag_who_paid'), style: const TextStyle(color: Colors.white70)),
              Wrap(spacing: 6, runSpacing: 2, children: [
                for (var m = 0; m < g.members.length; m++)
                  if (m != i)
                    FilterChip(
                      label: Text(g.members[m]),
                      selected: g.paid[i]?.contains(m) ?? false,
                      onSelected: (_) => _put(g.togglePaid(i, m)),
                    ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(L(t, 'ag_delivered')),
                value: g.delivered.contains(i),
                onChanged: (_) => _put(g.toggleDelivered(i)),
              ),
            ]),
          ),
        ),
      AppHeading(L(t, 'ag_members_total'), icon: Icons.people_alt_rounded),
      AppPanel(
        child: Column(children: [
          for (var m = 0; m < g.members.length; m++) _memberLine(g, m),
        ]),
      ),
      AppInfoCard(L(t, 'ag_record_only'), icon: Icons.menu_book_rounded),
    ]);
  }
}

// ===================================================== esnaf veresiye

class CreditBookTool extends StatefulWidget {
  final ToolContext t;
  const CreditBookTool(this.t, {super.key});
  @override
  State<CreditBookTool> createState() => _CreditBookState();
}

class _CreditBookState extends BookState<CreditBookTool> {
  @override
  ToolContext get t => widget.t;
  List<Customer> _c = [];
  String _shop = '';
  String _tpl = '';
  String? _open;
  final _search = TextEditingController();

  @override
  Future<void> load() async {
    _c = (await readList('customers')).map(Customer.fromJson).whereType<Customer>().toList();
    _shop = await t.store.read('shop') ?? '';
    _tpl = await t.store.read('template') ?? '';
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _set(List<Customer> c) {
    setState(() => _c = c);
    unawaited(t.store.writeList('customers', [for (final x in c) x.toJson()]));
  }

  void _put(Customer c) => _set([for (final x in _c) x.id == c.id ? c : x]);

  String get _template => _tpl.isEmpty ? L(t, 'vd_tpl_default') : _tpl;

  Future<void> _settings() async {
    final r = await editForm(context, t, L(t, 'vd_settings'), [
      F.text('shop', L(t, 'vd_shop'), initial: _shop),
      F.text('tpl', L(t, 'vd_template'), initial: _template),
    ]);
    if (r == null) return;
    final tpl = (r['tpl'] as String).trim();
    setState(() {
      _shop = r['shop'] as String;
      _tpl = tpl == L(t, 'vd_tpl_default') ? '' : tpl;
    });
    await t.store.write('shop', _shop);
    await t.store.write('template', _tpl);
  }

  Future<void> _edit([Customer? e]) async {
    final r = await editForm(context, t, L(t, e == null ? 'vd_new_customer' : 'edit'), [
      F.text('name', L(t, 'name'), initial: e?.name ?? '', must: true),
      F.text('phone', L(t, 'vd_phone'), initial: e?.phone ?? ''),
      F.money('limit', L(t, 'vd_limit'), initial: e == null || e.limit == 0 ? null : e.limit, must: false),
      F.text('note', L(t, 'note'), initial: e?.note ?? ''),
    ]);
    if (r == null) return;
    final c = (e ?? Customer(id: newId(), name: '')).copyWith(
      name: r['name'] as String,
      phone: r['phone'] as String,
      limit: r['limit'] as int? ?? 0,
      note: r['note'] as String,
    );
    _set([for (final x in _c) if (x.id != c.id) x, c]);
    setState(() => _open = c.id);
  }

  Future<void> _tx(Customer c, bool credit) async {
    final r = await editForm(context, t, '${L(t, credit ? 'vd_credit' : 'vd_payment')} · ${c.name}', [
      F.money('amount', L(t, 'amount'), initial: credit || c.balance <= 0 ? null : c.balance),
      F.date('date', L(t, 'date'), initial: DateTime.now()),
      F.text('note', L(t, credit ? 'vd_items' : 'note')),
    ]);
    if (r == null) return;
    final a = r['amount'] as int;
    _put(c.add(CreditTx(r['date'] as DateTime? ?? DateTime.now(), credit ? a : -a, r['note'] as String)));
  }

  String _reminder(Customer c) =>
      fillTemplate(_template, {'name': c.name, 'amount': mc(c.balance), 'shop': _shop.isEmpty ? '' : _shop}).trim();

  String _statement(Customer c) {
    final b = StringBuffer('${_shop.isEmpty ? '' : '$_shop\n'}${c.name}\n');
    var run = 0;
    for (final x in c.txs) {
      run += x.cents;
      b.writeln('${date(x.date)}  ${x.cents > 0 ? '+' : '−'}${mc(x.cents.abs())}'
          '${x.note.isEmpty ? '' : '  ${x.note}'}  = ${mc(run)}');
    }
    b.write('${L(t, 'balance')}: ${mc(c.balance)}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    Customer? open;
    for (final c in _c) {
      if (c.id == _open) open = c;
    }
    return open == null ? _list(context) : _detail(context, open);
  }

  Widget _list(BuildContext context) {
    final now = DateTime.now();
    final tot = creditTotals(_c);
    final q = _search.text.trim().folded;
    final list = [for (final c in _c) if (q.isEmpty || c.name.folded.contains(q) || c.phone.contains(q)) c]
      ..sort((a, b) => b.balance.compareTo(a.balance));
    return ToolList(children: [
      bar(
        onExport: () => exportCsv(context, t, 'credit_book', customersCsv(_c)),
        extra: [
          ActionChip(avatar: const Icon(Icons.storefront_rounded, size: 18), label: Text(L(t, 'vd_settings')), onPressed: _settings),
        ],
      ),
      AppPanel(
        child: Column(children: [
          line(L(t, 'vd_total_due'), mc(tot.$1), big: true),
          if (tot.$2 > 0) line(L(t, 'vd_overpaid'), mc(tot.$2)),
          line(L(t, 'vd_customers'), '${_c.where((c) => c.balance > 0).length} / ${_c.length}'),
          if (_c.any((c) => c.overLimit)) line(L(t, 'vd_over_limit'), '${_c.where((c) => c.overLimit).length}'),
        ]),
      ),
      AppButton(label: L(t, 'vd_new_customer'), icon: Icons.person_add_alt_1_rounded, onPressed: () => _edit()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppTextField(controller: _search, label: L(t, 'search'), onChanged: (_) => setState(() {})),
      ),
      if (list.isEmpty) emptyNote(t),
      for (final c in list)
        Card(
          child: ListTile(
            leading: Icon(c.overLimit ? Icons.warning_amber_rounded : Icons.person_rounded,
                color: c.overLimit ? Colors.orangeAccent : null),
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text([
              if (c.phone.isNotEmpty) c.phone,
              if (c.daysSincePayment(now) != null) L(t, 'vd_days').replaceAll('{n}', '${c.daysSincePayment(now)}'),
            ].join(' · ')),
            trailing: Text(mc(c.balance),
                style: TextStyle(fontWeight: FontWeight.w800, color: c.balance > 0 ? Colors.orangeAccent : Colors.lightGreenAccent)),
            onTap: () => setState(() => _open = c.id),
          ),
        ),
      AppInfoCard(L(t, 'vd_note'), icon: Icons.menu_book_rounded),
    ]);
  }

  Widget _detail(BuildContext context, Customer c) {
    final now = DateTime.now();
    var run = 0;
    final rows = <(CreditTx, int)>[];
    for (final x in c.txs) {
      run += x.cents;
      rows.add((x, run));
    }
    return ToolList(children: [
      _backRow(context, c.name, () => setState(() => _open = null)),
      AppPanel(
        child: Column(children: [
          line(L(t, 'balance'), mc(c.balance), big: true),
          if (c.limit > 0) line(L(t, 'vd_limit'), mc(c.limit)),
          if (c.daysSincePayment(now) != null) line(L(t, 'vd_last_payment'), L(t, 'vd_days').replaceAll('{n}', '${c.daysSincePayment(now)}')),
          if (c.phone.isNotEmpty) line(L(t, 'vd_phone'), c.phone),
        ]),
      ),
      if (c.overLimit) AppInfoCard(L(t, 'vd_over_limit'), icon: Icons.warning_amber_rounded),
      Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
        AppButton(label: L(t, 'vd_credit'), icon: Icons.add_shopping_cart_rounded, onPressed: () => _tx(c, true)),
        AppButton(label: L(t, 'vd_payment'), icon: Icons.payments_rounded, onPressed: () => _tx(c, false)),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          if (c.balance > 0)
            ActionChip(
              avatar: const Icon(Icons.notifications_active_rounded, size: 18),
              label: Text(L(t, 'vd_remind')),
              onPressed: () => shareText(context, t, _reminder(c)),
            ),
          ActionChip(
            avatar: const Icon(Icons.receipt_long_rounded, size: 18),
            label: Text(L(t, 'vd_statement')),
            onPressed: () => shareText(context, t, _statement(c)),
          ),
          ActionChip(avatar: const Icon(Icons.edit_rounded, size: 18), label: Text(L(t, 'edit')), onPressed: () => _edit(c)),
          ActionChip(
            avatar: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(L(t, 'delete')),
            onPressed: () async {
              if (await confirmDelete(context, t)) {
                _set([for (final x in _c) if (x.id != c.id) x]);
                setState(() => _open = null);
              }
            },
          ),
        ]),
      ),
      if (c.note.isNotEmpty) AppInfoCard(c.note, icon: Icons.sticky_note_2_rounded),
      AppHeading(L(t, 'records'), icon: Icons.history_rounded),
      if (rows.isEmpty) emptyNote(t),
      for (final r in rows.reversed)
        Card(
          child: ListTile(
            leading: Icon(r.$1.cents > 0 ? Icons.north_east_rounded : Icons.south_west_rounded,
                color: r.$1.cents > 0 ? Colors.orangeAccent : Colors.lightGreenAccent),
            title: Text('${L(t, r.$1.cents > 0 ? 'vd_credit' : 'vd_payment')} · ${mc(r.$1.cents.abs())}'),
            subtitle: Text([date(r.$1.date), if (r.$1.note.isNotEmpty) r.$1.note].join(' · ')),
            trailing: Text(mc(r.$2)),
            onLongPress: () async {
              if (await confirmDelete(context, t)) {
                _put(c.copyWith(txs: [for (final x in c.txs) if (!identical(x, r.$1)) x]));
              }
            },
          ),
        ),
      AppInfoCard(L(t, 'vd_share_note'), icon: Icons.share_rounded),
    ]);
  }
}

// ===================================================== sepet enflasyonu

class BasketTool extends StatefulWidget {
  final ToolContext t;
  const BasketTool(this.t, {super.key});
  @override
  State<BasketTool> createState() => _BasketState();
}

class _BasketState extends BookState<BasketTool> {
  @override
  ToolContext get t => widget.t;
  List<BasketItem> _i = [];
  String? _expanded;

  @override
  Future<void> load() async {
    _i = (await readList('basket')).map(BasketItem.fromJson).whereType<BasketItem>().toList();
  }

  void _set(List<BasketItem> i) {
    setState(() => _i = i);
    unawaited(t.store.writeList('basket', [for (final x in i) x.toJson()]));
  }

  void _put(BasketItem i) => _set([for (final x in _i) x.id == i.id ? i : x]);

  Future<void> _edit([BasketItem? e]) async {
    final r = await editForm(context, t, L(t, e == null ? 'add' : 'edit'), [
      F.text('name', L(t, 'item'), initial: e?.name ?? '', must: true),
      F.text('unit', L(t, 'bs_unit'), initial: e?.unit ?? ''),
      F.text('qty', L(t, 'bs_qty'), initial: e == null ? '1' : formatNumber(e.qty)),
    ]);
    if (r == null) return;
    final q = parseNumber(r['qty'] as String);
    final it = (e ?? BasketItem(id: newId(), name: '')).copyWith(
      name: r['name'] as String,
      unit: r['unit'] as String,
      qty: q == null || q <= 0 ? 1 : q,
    );
    _set([for (final x in _i) if (x.id != it.id) x, it]);
    if (e == null) await _price(it);
  }

  Future<void> _price(BasketItem it) async {
    final r = await editForm(context, t, '${L(t, 'bs_add_price')} · ${it.name}', [
      F.money('price', L(t, 'price'), initial: it.last?.cents),
      F.date('date', L(t, 'date'), initial: DateTime.now()),
      F.text('store', L(t, 'bs_store'), initial: it.last?.store ?? ''),
    ]);
    if (r == null) return;
    BasketItem cur = it;
    for (final x in _i) {
      if (x.id == it.id) cur = x;
    }
    _put(cur.copyWith(
      prices: [...cur.prices, PricePoint(r['date'] as DateTime? ?? DateTime.now(), r['price'] as int, r['store'] as String)]
        ..sort((a, b) => a.date.compareTo(b.date)),
    ));
  }

  String _pct(double? v) => v == null ? '—' : '${v >= 0 ? '+' : ''}${fmtPct(v)}';

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final ms = basketIndex(_i, DateTime.now());
    final ch = basketChanges(ms);
    final shown = ms.length > 13 ? ms.sublist(ms.length - 13) : ms;
    return ToolList(children: [
      bar(onExport: () => exportCsv(context, t, 'basket', basketCsv(_i))),
      AppPanel(
        child: Column(children: [
          line(L(t, 'bs_index'), ms.isEmpty ? '—' : formatNumber(ms.last.index, digits: 1), big: true),
          line(L(t, 'bs_cost'), ms.isEmpty ? '—' : mc(ms.last.cost)),
          line(L(t, 'vs_last_month'), _pct(ch.$1)),
          line(L(t, 'bs_vs_year'), _pct(ch.$2)),
          if (ms.length > 1) line(L(t, 'bs_since_start'), _pct(ms.last.index - 100)),
        ]),
      ),
      if (shown.length > 1)
        AppPanel(
          child: SizedBox(
            height: 150,
            child: CustomPaint(size: Size.infinite, painter: _IndexBars([for (final m in shown) m.index], AppLook.of(context).accent)),
          ),
        ),
      AppButton(label: L(t, 'add'), icon: Icons.add_shopping_cart_rounded, onPressed: () => _edit()),
      if (_i.isEmpty) emptyNote(t),
      for (final it in _i)
        Card(
          child: Column(children: [
            ListTile(
              title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text([
                '${formatNumber(it.qty)} ${it.unit}'.trim(),
                if (it.last != null) '${L(t, 'price')}: ${mc(it.last!.cents)} (${date(it.last!.date)})',
              ].join(' · ')),
              trailing: Text(_pct(it.change),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: (it.change ?? 0) > 0 ? Colors.orangeAccent : Colors.lightGreenAccent)),
              onTap: () => setState(() => _expanded = _expanded == it.id ? null : it.id),
            ),
            if (_expanded == it.id) ...[
              for (final p in it.prices.reversed)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.sell_rounded, size: 18),
                  title: Text(mc(p.cents)),
                  subtitle: Text([date(p.date), if (p.store.isNotEmpty) p.store].join(' · ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => _put(it.copyWith(prices: [for (final x in it.prices) if (!identical(x, p)) x])),
                  ),
                ),
              OverflowBar(alignment: MainAxisAlignment.end, children: [
                TextButton.icon(onPressed: () => _edit(it), icon: const Icon(Icons.edit_rounded), label: Text(L(t, 'edit'))),
                TextButton.icon(
                  onPressed: () async {
                    if (await confirmDelete(context, t)) _set([for (final x in _i) if (x.id != it.id) x]);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(L(t, 'delete')),
                ),
              ]),
            ],
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(onPressed: () => _price(it), icon: const Icon(Icons.add_rounded), label: Text(L(t, 'bs_add_price'))),
            ),
          ]),
        ),
      AppInfoCard(L(t, 'bs_note'), icon: Icons.info_outline_rounded),
    ]);
  }
}

/// Endeks çubukları (100 çizgisi işaretli).
class _IndexBars extends CustomPainter {
  final List<double> v;
  final Color color;
  _IndexBars(this.v, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.isEmpty) return;
    final lo = math.min(100.0, v.reduce(math.min)) * 0.95;
    final hi = math.max(100.0, v.reduce(math.max)) * 1.02;
    double y(double x) => size.height - (x - lo) / math.max(1e-9, hi - lo) * size.height;
    final w = size.width / v.length;
    final p = Paint()..color = color;
    for (var i = 0; i < v.length; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(i * w + w * 0.15, y(v[i]), (i + 1) * w - w * 0.15, size.height), const Radius.circular(4)),
        p..color = i == v.length - 1 ? color : color.withValues(alpha: 0.55),
      );
    }
    final base = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y(100)), Offset(size.width, y(100)), base);
  }

  @override
  bool shouldRepaint(_IndexBars old) => old.v != v || old.color != color;
}

// ===================================================== mini kasa ve stok

class MiniPosTool extends StatefulWidget {
  final ToolContext t;
  const MiniPosTool(this.t, {super.key});
  @override
  State<MiniPosTool> createState() => _MiniPosState();
}

class _MiniPosState extends BookState<MiniPosTool> {
  @override
  ToolContext get t => widget.t;
  List<Product> _p = [];
  List<Sale> _s = [];
  final Map<String, int> _cart = {};
  int _tab = 0; // 0 satış, 1 ürünler, 2 rapor
  int _range = 0; // 0 bugün, 1 7 gün, 2 bu ay
  int _method = 0;

  @override
  Future<void> load() async {
    _p = (await readList('products')).map(Product.fromJson).whereType<Product>().toList();
    _s = (await readList('sales')).map(Sale.fromJson).whereType<Sale>().toList();
  }

  void _saveProducts(List<Product> p) {
    _p = p;
    unawaited(t.store.writeList('products', [for (final x in p) x.toJson()]));
  }

  void _saveSales(List<Sale> s) {
    // Cihazda yer kaplamasın: en yeni 5000 satış tutulur.
    _s = s.length > 5000 ? s.sublist(s.length - 5000) : s;
    unawaited(t.store.writeList('sales', [for (final x in _s) x.toJson()]));
  }

  Future<void> _edit([Product? e]) async {
    final r = await editForm(context, t, L(t, e == null ? 'mk_new_product' : 'edit'), [
      F.text('name', L(t, 'name'), initial: e?.name ?? '', must: true),
      F.money('price', L(t, 'mk_sale_price'), initial: e?.price),
      F.money('cost', L(t, 'mk_cost'), initial: e == null || e.cost == 0 ? null : e.cost, must: false),
      F.integer('stock', L(t, 'mk_stock'), initial: e?.stock ?? 0),
      F.integer('low', L(t, 'mk_low'), initial: e?.low ?? 0),
    ]);
    if (r == null) return;
    final p = (e ?? Product(id: newId(), name: '', price: 0)).copyWith(
      name: r['name'] as String,
      price: r['price'] as int,
      cost: r['cost'] as int? ?? 0,
      stock: r['stock'] as int,
      low: math.max(0, r['low'] as int),
    );
    setState(() => _saveProducts([for (final x in _p) if (x.id != p.id) x, p]));
  }

  Future<void> _restock(Product p) async {
    final r = await editForm(context, t, '${L(t, 'mk_restock')} · ${p.name}', [
      F.integer('qty', L(t, 'quantity'), initial: 1),
    ]);
    if (r == null) return;
    setState(() => _saveProducts([for (final x in _p) x.id == p.id ? x.copyWith(stock: x.stock + (r['qty'] as int)) : x]));
  }

  int get _cartTotal {
    var s = 0;
    for (final p in _p) {
      s += (_cart[p.id] ?? 0) * p.price;
    }
    return s;
  }

  void _checkout() {
    if (_cart.values.every((q) => q <= 0)) return;
    final r = checkout(_p, _cart, DateTime.now(), method: _method);
    setState(() {
      _saveProducts(r.$2);
      _saveSales([..._s, r.$1]);
      _cart.clear();
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('${L(t, 'mk_saved')} · ${mc(r.$1.total)}')));
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    return ToolList(children: [
      bar(),
      Choice<int>(
        values: const [0, 1, 2],
        labels: [L(t, 'mk_sell'), L(t, 'mk_products'), L(t, 'summary')],
        selected: _tab,
        onChanged: (v) => setState(() => _tab = v),
      ),
      ...switch (_tab) { 1 => _products(context), 2 => _report(context), _ => _sell(context) },
      AppInfoCard(L(t, 'mk_note'), icon: Icons.point_of_sale_rounded),
    ]);
  }

  List<Widget> _sell(BuildContext context) {
    final low = _p.where((p) => p.isLow).toList();
    final methods = Ls(t, 'methods');
    return [
      if (_p.isEmpty) ...[
        emptyNote(t),
        AppButton(label: L(t, 'mk_new_product'), icon: Icons.add_box_rounded, onPressed: () => _edit()),
      ],
      if (low.isNotEmpty) AppInfoCard('${L(t, 'mk_low_stock')}: ${low.map((p) => p.name).join(', ')}', icon: Icons.inventory_2_rounded),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in _p)
            ActionChip(
              avatar: (_cart[p.id] ?? 0) > 0 ? CircleAvatar(child: Text('${_cart[p.id]}')) : null,
              label: Text('${p.name}\n${mc(p.price)} · ${p.stock}', textAlign: TextAlign.center),
              onPressed: () => setState(() => _cart[p.id] = (_cart[p.id] ?? 0) + 1),
            ),
        ]),
      ),
      if (_cart.values.any((q) => q > 0))
        AppPanel(
          child: Column(children: [
            for (final p in _p)
              if ((_cart[p.id] ?? 0) > 0)
                Row(children: [
                  Expanded(child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: () => setState(() {
                      final q = (_cart[p.id] ?? 0) - 1;
                      if (q <= 0) {
                        _cart.remove(p.id);
                      } else {
                        _cart[p.id] = q;
                      }
                    }),
                  ),
                  Text('${_cart[p.id]}'),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: () => setState(() => _cart[p.id] = (_cart[p.id] ?? 0) + 1),
                  ),
                  Text(mc((_cart[p.id] ?? 0) * p.price)),
                ]),
            line(L(t, 'sum'), mc(_cartTotal), big: true),
            Pick<int>(
              label: L(t, 'method'),
              values: List.generate(methods.length, (i) => i),
              text: (i) => methods[i],
              value: _method.clamp(0, methods.length - 1),
              onChanged: (i) => setState(() => _method = i),
            ),
          ]),
        ),
      if (_cart.values.any((q) => q > 0))
        Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
          AppButton(label: L(t, 'mk_record_sale'), icon: Icons.check_circle_rounded, onPressed: _checkout),
          TextButton(onPressed: () => setState(_cart.clear), child: Text(t.core('cancel'))),
        ]),
    ];
  }

  List<Widget> _products(BuildContext context) => [
        AppButton(label: L(t, 'mk_new_product'), icon: Icons.add_box_rounded, onPressed: () => _edit()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ActionChip(
              avatar: const Icon(Icons.file_download_rounded, size: 18),
              label: Text(L(t, 'export_csv')),
              onPressed: () => exportCsv(context, t, 'products', productsCsv(_p)),
            ),
          ),
        ),
        if (_p.isEmpty) emptyNote(t),
        for (final p in [..._p]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())))
          Card(
            child: ListTile(
              leading: Icon(p.isLow ? Icons.warning_amber_rounded : Icons.inventory_2_rounded,
                  color: p.isLow ? Colors.orangeAccent : null),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text([
                '${L(t, 'mk_stock')}: ${p.stock}',
                if (p.cost > 0) '${L(t, 'mk_cost')}: ${mc(p.cost)}',
              ].join(' · ')),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(mc(p.price), style: const TextStyle(fontWeight: FontWeight.w800)),
                IconButton(tooltip: L(t, 'mk_restock'), icon: const Icon(Icons.move_to_inbox_rounded), onPressed: () => _restock(p)),
              ]),
              onTap: () => _edit(p),
              onLongPress: () async {
                if (await confirmDelete(context, t)) setState(() => _saveProducts([for (final x in _p) if (x.id != p.id) x]));
              },
            ),
          ),
      ];

  List<Widget> _report(BuildContext context) {
    final now = DateTime.now();
    final from = switch (_range) {
      1 => DateTime(now.year, now.month, now.day - 6),
      2 => DateTime(now.year, now.month),
      _ => DateTime(now.year, now.month, now.day),
    };
    final s = summarize(_s, from, now);
    final recent = [for (final x in _s) if (!x.date.isBefore(from)) x]..sort((a, b) => b.date.compareTo(a.date));
    final methods = Ls(t, 'methods');
    return [
      Choice<int>(
        values: const [0, 1, 2],
        labels: [L(t, 'mk_today'), L(t, 'mk_7days'), L(t, 'mk_month')],
        selected: _range,
        onChanged: (v) => setState(() => _range = v),
      ),
      AppPanel(
        child: Column(children: [
          line(L(t, 'mk_revenue'), mc(s.revenue), big: true),
          if (_p.any((p) => p.cost > 0)) line(L(t, 'mk_profit'), mc(s.profit)),
          line(L(t, 'mk_sales'), '${s.count}'),
          line(L(t, 'mk_items_sold'), '${s.items}'),
        ]),
      ),
      if (s.top.isNotEmpty) ...[
        AppHeading(L(t, 'mk_top'), icon: Icons.leaderboard_rounded),
        AppPanel(child: Column(children: [for (final x in s.top) line('${x.$1} ×${x.$2}', mc(x.$3))])),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ActionChip(
            avatar: const Icon(Icons.file_download_rounded, size: 18),
            label: Text(L(t, 'export_csv')),
            onPressed: () => exportCsv(context, t, 'sales', salesCsv(_s)),
          ),
        ),
      ),
      for (final x in recent.take(100))
        Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_rounded),
            title: Text(x.lines.map((l) => '${l.name} ×${l.qty}').join(', '), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${date(x.date)} ${TimeOfDay.fromDateTime(x.date).format(context)}'
                '${x.method >= 0 && x.method < methods.length ? ' · ${methods[x.method]}' : ''}'),
            trailing: Text(mc(x.total), style: const TextStyle(fontWeight: FontWeight.w800)),
            onLongPress: () async {
              if (await confirmDelete(context, t)) {
                setState(() {
                  _saveProducts(refund(_p, x));
                  _saveSales([for (final y in _s) if (y.id != x.id) y]);
                });
              }
            },
          ),
        ),
      if (recent.isNotEmpty) AppInfoCard(L(t, 'mk_undo_hint'), icon: Icons.undo_rounded),
    ];
  }
}

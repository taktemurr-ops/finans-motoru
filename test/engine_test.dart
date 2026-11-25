import 'package:finans_motoru/finans_motoru.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:studio_core/app/services/ads.dart';
import 'package:studio_core/app/services/purchases.dart';
import 'package:studio_core/core/save_store.dart';

void main() {
  test('20 araç, 33 dilde ad ve açıklama, finans uyarısı', () {
    expect(finansTools.length, 20);
    expect(finansTools.map((t) => t.id).toSet().length, 20);
    for (final t in finansTools) {
      expect(t.title.length, 33, reason: t.id);
      expect(t.tagline.length, 33, reason: t.id);
      expect(t.id.startsWith('uyg-'), isTrue);
      expect(t.disclaimer, AppDisclaimer.finance, reason: t.id);
      expect(finansCategories.any((c) => c.id == t.category), isTrue, reason: t.id);
    }
    expect(finansHubTitle.length, 33);
  });

  test('biçimlendirme ve tutar okuma', () {
    expect(fmtMoney(1234567.891, 'tr', '₺'), '1.234.567,89 ₺');
    expect(fmtMoney(-5, 'en'), '-5.00');
    expect(parseCents('1.234,5'), 123450);
    expect(parseCents('1,234.56'), 123456);
    expect(parseCents('١٢٣'), 12300);
    expect(parseCents('abc'), isNull);
    expect(parseCents(''), isNull);
  });

  test('kredi: anüite ve vergiler', () {
    final r = loan(100000, 0.02, 12);
    expect(r.payment, closeTo(9455.96, 0.01));
    expect(r.rows.last.balance, closeTo(0, 1e-6));
    expect(r.total, closeTo(9455.96 * 12, 0.5));
    final z = loan(1200, 0, 12);
    expect(z.payment, 100);
    // KKDF + BSMV %30: faize eklenir, ana para aynı kalır.
    final tr = loan(100000, 0.03, 24, taxRate: 0.30);
    expect(tr.rows.fold<double>(0, (a, x) => a + x.principal), closeTo(100000, 0.01));
    expect(tr.tax, closeTo(tr.interest * 0.30, 0.01));
    expect(loan(-1, 0.01, 12).rows, isEmpty);
  });

  test('bileşik getiri ve stopaj', () {
    final g = grow(1000, 0, 0.12, 12);
    expect(g.finalValue, closeTo(1000 * 1.126825, 0.01));
    final s = grow(0, 100, 0, 10);
    expect(s.finalValue, closeTo(1000, 1e-9));
    expect(s.deposited, 1000);
    final w = grow(1000, 0, 0.12, 12, withholding: 0.15);
    expect(w.tax, greaterThan(0));
    expect(w.finalValue, lessThan(g.finalValue));
  });

  test('indirim, KDV, bölüşme', () {
    expect(discounted(100, [20, 10]), closeTo(72, 1e-9));
    final a = vat(100, 20, included: false);
    expect(a.$3, closeTo(120, 1e-9));
    final b = vat(120, 20, included: true);
    expect(b.$1, closeTo(100, 1e-9));
    expect(b.$2, closeTo(20, 1e-9));
    final s = split(1000, 10, 3, roundUp: true);
    expect(s.$3, 367);
    expect(split(100, 0, 0).$3, 100);
  });

  test('taksit: etkin faiz', () {
    expect(effectiveMonthlyRate(1200, 100, 12), closeTo(0, 1e-6));
    final r = effectiveMonthlyRate(1000, 100, 12);
    expect(presentValue(100, 12, r), closeTo(1000, 0.01));
    expect(r, greaterThan(0.02));
  });

  test('kredi kartı', () {
    final p = cardPayoff(1000, 0.02, 100);
    expect(p.months, greaterThan(10));
    expect(p.total, closeTo(1000 + p.interest, 0.01));
    expect(cardPayoff(1000, 0.05, 40).months, -1);
    final z = cardPayoff(1000, 0, 250);
    expect(z.months, 4);
  });

  test('kira ve enflasyon tabloları', () {
    expect(rentCapFor('2026-11')!.$2, 31.23);
    expect(rentCapFor('2027-03')!.$1, '2026-11');
    expect(rentCapFor('2025-01')!.$1, '2026-01');
    expect(newRent(10000, 31.23), closeTo(13123, 1e-6));
    expect(cpiFactor(2024, 2025), closeTo(1.3089, 1e-9));
    expect(cpiFactor(2025, 2024), closeTo(1 / 1.3089, 1e-9));
    expect(cpiFactor(2020, 2020), 1);
  });

  test('gelir vergisi 2026', () {
    const w = TaxTariff.wage2026, n = TaxTariff.nonWage2026;
    expect(w.taxOn(190000), closeTo(28500, 0.01));
    expect(w.taxOn(400000), closeTo(70500, 0.01));
    expect(w.taxOn(1500000), closeTo(367500, 0.01));
    expect(n.taxOn(1000000), closeTo(232500, 0.01));
    expect(n.taxOn(5300000), closeTo(1737500, 0.01));
    expect(w.taxOn(5300000), closeTo(1697500, 0.01));
    expect(w.marginal(600000), 0.27);
    expect(TaxTariff.fromJson(w.toJson())!.taxOn(800000), w.taxOn(800000));
  });

  test('zekât', () {
    final below = zakat(cash: 1000, goldGrams: 0, goldPrice: 3000);
    expect(below.above, isFalse);
    expect(below.due, 0);
    final z = zakat(cash: 400000, goldGrams: 10, goldPrice: 3000, debts: 30000);
    expect(z.net, 400000);
    expect(z.nisab, closeTo(240540, 0.01));
    expect(z.due, 10000);
  });

  test('birim fiyat', () {
    expect(unitPrice(45, 500, 'g'), closeTo(0.09, 1e-12));
    expect(cheapest([(45, 500, 'g'), (80, 1, 'kg')]), 1);
    expect(cheapest([(10, 1, 'L'), (1, 1, 'kg')]), 0); // farklı taban birim karşılaştırılmaz
    expect(unitPrice(1, 0, 'g'), isNull);
  });

  test('bütçe defteri: özet, uyarı, tekrarlayan, CSV', () {
    final m = DateTime(2026, 1);
    var l = Ledger(
      entries: [
        Entry(id: 'a', date: DateTime(2026, 1, 3), cents: 500000, income: true, category: 'Maaş'),
        Entry(id: 'b', date: DateTime(2026, 1, 5), cents: 90000, income: false, category: 'Market', method: 1, note: 'pazar, sebze'),
        Entry(id: 'c', date: DateTime(2026, 2, 5), cents: 1000, income: false, category: 'Market'),
      ],
      budgets: const {'Market': 100000},
      rules: [Rule(id: 'r', title: 'Kira', cents: 200000, income: false, category: 'Konut', next: DateTime(2026, 1, 31))],
    );
    final s = l.month(m);
    expect(s.income, 500000);
    expect(s.expense, 90000);
    expect(s.byMethod[1], 90000);
    expect(l.warnings(m).single.$1, 'Market');
    l = l.postDue(DateTime(2026, 3, 1));
    // 31 Ocak, 28 Şubat (ay sonu taşmaz)
    final rent = l.entries.where((e) => e.ruleId == 'r').toList();
    expect(rent.length, 2);
    expect(rent.map((e) => e.date.day).toSet(), {31, 28});
    expect(l.rules.single.next, DateTime(2026, 3, 28));
    expect(l.search('sebze').single.id, 'b');
    final csv = l.csv(['Kart', 'Nakit', 'Havale']);
    expect(csv.split('\r\n').first, 'date,type,category,method,amount,note');
    expect(csv.contains('"pazar, sebze"'), isTrue);
    final back = Ledger.fromJson(l.toJson());
    expect(back.entries.length, l.entries.length);
    expect(back.budgets['Market'], 100000);
  });

  test('borç, hedef, abonelik, fatura, harçlık', () {
    var d = Debt(id: 'd', name: 'Ali', cents: 10000, owe: true, created: DateTime(2026, 1, 1), due: DateTime(2026, 2, 1));
    d = d.pay(4000, DateTime(2026, 1, 10)).pay(99999, DateTime(2026, 1, 20));
    expect(d.settled, isTrue);
    expect(d.paid, 10000);
    expect(Debt.fromJson(d.toJson())!.remaining, 0);
    expect(debtTotals([d]), (0, 0));

    final g = Goal(id: 'g', title: 'Tatil', target: 120000, created: DateTime(2026, 1, 1), deadline: DateTime(2026, 7, 1))
        .move(20000, DateTime(2026, 1, 2))
        .move(-50000, DateTime(2026, 1, 3));
    expect(g.saved, 0); // çekme, birikeni aşamaz
    expect(g.perMonth(DateTime(2026, 1, 15)), 20000);

    final s = Sub(id: 's', name: 'Müzik', cents: 1200, period: 'year', next: DateTime(2025, 3, 10));
    expect(s.monthly, 100);
    expect(s.upcoming(DateTime(2026, 11, 25)), DateTime(2027, 3, 10));
    expect(advance(DateTime(2026, 1, 31), 'month'), DateTime(2026, 2, 28));
    expect(advance(DateTime(2024, 2, 29), 'year'), DateTime(2025, 2, 28));

    var b = Bill(id: 'b', name: 'Elektrik', cents: 50000, day: 31);
    expect(b.dueIn(DateTime(2026, 2)), DateTime(2026, 2, 28));
    b = b.markPaid(DateTime(2026, 2), 48000);
    expect(b.nextDue(DateTime(2026, 2, 10)), DateTime(2026, 3, 31));
    expect(Bill.fromJson(b.toJson())!.paid['2026-02'], 48000);

    final k = const Kid(id: 'k', name: 'Ece', weekly: 5000).add(5000, DateTime(2026, 1, 1), '').add(-1500, DateTime(2026, 1, 2), 'kitap');
    expect(k.balance, 3500);
    expect(kidsCsv([k]).split('\r\n').length, 3);
  });


  test('konut kredisi: ek ödeme vadeyi kısaltır, faiz tasarrufu', () {
    final b = mortgage(1000000, 0.02, 120);
    expect(b.months, 120);
    expect(b.payment, closeTo(loan(1000000, 0.02, 120).payment, 1e-6));
    expect(b.rows.last.balance, closeTo(0, 1e-6));
    expect(b.interestSaved, closeTo(0, 1e-6));
    final e = mortgage(1000000, 0.02, 120, extra: 5000, lump: 100000, lumpMonth: 12);
    expect(e.months, lessThan(120));
    expect(e.payment, b.payment);
    expect(e.interest, lessThan(b.interest));
    expect(e.interestSaved, closeTo(b.interest - e.interest, 1e-6));
    expect(e.rows.last.balance, closeTo(0, 0.01));
    final paid = e.rows.fold<double>(0, (a, r) => a + r.principal);
    expect(paid, closeTo(1000000, 0.01));
    expect(mortgage(0, 0.02, 120).rows, isEmpty);
    expect(monthlyFromAnnual(0.24), closeTo(0.02, 1e-12));
  });

  test('emeklilik: birikim, reel değer ve gereken katkı', () {
    final r = retirement(age: 30, retireAge: 31, savings: 0, monthly: 100, annualReturn: 0);
    expect(r.yearly.length, 1);
    expect(r.atRetirement, closeTo(1200, 1e-9));
    expect(r.deposited, closeTo(1200, 1e-9));
    expect(r.monthlyIncome, closeTo(1200 / 300, 1e-9));
    final g = retirement(age: 30, retireAge: 60, savings: 10000, monthly: 1000, annualReturn: 0.07, raise: 0.03, inflation: 0.02);
    expect(g.yearly.length, 30);
    expect(g.atRetirement, greaterThan(g.deposited));
    expect(g.atRetirementReal, lessThan(g.atRetirement));
    expect(annuityPayment(1200, 0, 12), 100);
    expect(annuityPayment(100000, 0.01, 12), closeTo(8884.88, 0.01));
    final need = requiredMonthly(targetReal: 2000, age: 30, retireAge: 60, savings: 0, annualReturn: 0.05, inflation: 0.02)!;
    final chk = retirement(age: 30, retireAge: 60, savings: 0, monthly: need, annualReturn: 0.05, inflation: 0.02);
    expect(chk.monthlyIncomeReal, closeTo(2000, 0.01));
    expect(requiredMonthly(targetReal: 10, age: 60, retireAge: 50, savings: 0, annualReturn: 0.05), isNull);
    expect(retirement(age: 60, retireAge: 50, savings: 1, monthly: 1, annualReturn: 0).yearly, isEmpty);
  });

  test('net varlık: toplamlar ve aylık kayıt', () {
    final (a, l, n) = netWorth([(true, 50000), (true, 25000), (false, 30000)]);
    expect((a, l, n), (75000, 30000, 45000));
    var s = upsertSnapshot([], DateTime(2026, 3, 5), 100, 40);
    s = upsertSnapshot(s, DateTime(2026, 3, 20), 120, 40);
    expect(s.length, 1);
    expect(s.single['a'], 120);
    s = upsertSnapshot(s, DateTime(2026, 1, 2), 10, 0);
    expect([for (final x in s) x['m']], ['2026-01', '2026-03']);
  });

  for (final t in [
    'uyg-butce-ve-harcama-takibi', 'uyg-kredi-hesaplayici', 'uyg-faiz-ve-birikim-hesaplayici', 'uyg-indirim-ve-kdv-hesaplayici',
    'uyg-hesap-bolusme-ve-bahsis', 'uyg-borc-takibi', 'uyg-abonelik-takibi', 'uyg-fatura-hatirlatici', 'uyg-birikim-hedefi',
    'uyg-harclik-takibi', 'uyg-birim-fiyat-karsilastirma', 'uyg-taksit-hesaplayici', 'uyg-kredi-karti-borc-planlayici',
    'uyg-kira-artis-hesaplayici', 'uyg-enflasyon-hesaplayici', 'uyg-gelir-vergisi-hesaplayici', 'uyg-zekat-hesaplayici',
    'uyg-konut-kredisi-hesaplayici', 'uyg-emeklilik-hesaplayici', 'uyg-net-varlik-takibi',
  ]) {
    testWidgets('araç ekranı açılır: $t', (tester) async {
      final s = AppServices(hubId: 'm', backend: MemoryBackend(), ads: NoAdsService(), purchases: NoPurchaseService());
      final tool = finansTool(t);
      final ctx = ToolContext(toolId: t, lang: 'tr', store: s.storeFor(t), services: s);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: AppLook(style: finansHubStyle, child: Scaffold(body: Builder(builder: (c) => tool.builder(c, ctx)))),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  }
}

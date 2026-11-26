/// Üretilmiş dosya (proto/apps/finans/mkengine.py). Finans ve Hesaplama'nın 20 aracı.
library;

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import 'tools/books_ui.dart';
import 'tools/calcs.dart';
import 'tools/plans.dart';
import 'tx.dart';

/// Kategoriler (merkezdeki çip sırası).
final List<AppCategory> finansCategories = [
  AppCategory(id: 'track', title: kFinCat['cat_track']!, icon: Icons.account_balance_wallet_rounded),
  AppCategory(id: 'loan', title: kFinCat['cat_loan']!, icon: Icons.percent_rounded),
  AppCategory(id: 'shop', title: kFinCat['cat_shop']!, icon: Icons.shopping_cart_rounded),
  AppCategory(id: 'tax', title: kFinCat['cat_tax']!, icon: Icons.gavel_rounded),
];

/// Bütün araçlar (katalog sırası). Hepsi finans uyarısı gösterir.
final List<AppTool> finansTools = [
  AppTool(
    id: 'uyg-butce-ve-harcama-takibi',
    title: kFinTitle['uyg-butce-ve-harcama-takibi']!,
    tagline: kFinTag['uyg-butce-ve-harcama-takibi']!,
    icon: Icons.account_balance_wallet_rounded,
    color: const Color(0xFF66BB6A),
    category: 'track',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['budget', 'expense', 'gider', 'harcama', 'csv'],
    builder: (context, t) => BudgetTool(t),
  ),
  AppTool(
    id: 'uyg-kredi-hesaplayici',
    title: kFinTitle['uyg-kredi-hesaplayici']!,
    tagline: kFinTag['uyg-kredi-hesaplayici']!,
    icon: Icons.credit_score_rounded,
    color: const Color(0xFF42A5F5),
    category: 'loan',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['loan', 'kredi', 'faiz', 'kkdf', 'bsmv'],
    builder: (context, t) => LoanTool(t),
  ),
  AppTool(
    id: 'uyg-faiz-ve-birikim-hesaplayici',
    title: kFinTitle['uyg-faiz-ve-birikim-hesaplayici']!,
    tagline: kFinTag['uyg-faiz-ve-birikim-hesaplayici']!,
    icon: Icons.trending_up_rounded,
    color: const Color(0xFF26A69A),
    category: 'loan',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['interest', 'mevduat', 'compound'],
    builder: (context, t) => GrowthTool(t),
  ),
  AppTool(
    id: 'uyg-indirim-ve-kdv-hesaplayici',
    title: kFinTitle['uyg-indirim-ve-kdv-hesaplayici']!,
    tagline: kFinTag['uyg-indirim-ve-kdv-hesaplayici']!,
    icon: Icons.sell_rounded,
    color: const Color(0xFFFF7043),
    category: 'shop',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['kdv', 'vat', 'discount', '%'],
    builder: (context, t) => DiscountTool(t),
  ),
  AppTool(
    id: 'uyg-hesap-bolusme-ve-bahsis',
    title: kFinTitle['uyg-hesap-bolusme-ve-bahsis']!,
    tagline: kFinTag['uyg-hesap-bolusme-ve-bahsis']!,
    icon: Icons.room_service_rounded,
    color: const Color(0xFFAB47BC),
    category: 'shop',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['split', 'tip', 'bahşiş'],
    builder: (context, t) => SplitTool(t),
  ),
  AppTool(
    id: 'uyg-borc-takibi',
    title: kFinTitle['uyg-borc-takibi']!,
    tagline: kFinTag['uyg-borc-takibi']!,
    icon: Icons.handshake_rounded,
    color: const Color(0xFFFFA726),
    category: 'track',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['debt', 'alacak'],
    builder: (context, t) => DebtTool(t),
  ),
  AppTool(
    id: 'uyg-abonelik-takibi',
    title: kFinTitle['uyg-abonelik-takibi']!,
    tagline: kFinTag['uyg-abonelik-takibi']!,
    icon: Icons.autorenew_rounded,
    color: const Color(0xFF5C6BC0),
    category: 'track',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['subscription'],
    builder: (context, t) => SubsTool(t),
  ),
  AppTool(
    id: 'uyg-fatura-hatirlatici',
    title: kFinTitle['uyg-fatura-hatirlatici']!,
    tagline: kFinTag['uyg-fatura-hatirlatici']!,
    icon: Icons.receipt_long_rounded,
    color: const Color(0xFFEF5350),
    category: 'track',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['bill', 'reminder'],
    builder: (context, t) => BillTool(t),
  ),
  AppTool(
    id: 'uyg-birikim-hedefi',
    title: kFinTitle['uyg-birikim-hedefi']!,
    tagline: kFinTag['uyg-birikim-hedefi']!,
    icon: Icons.savings_rounded,
    color: const Color(0xFFFFCA28),
    category: 'track',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['savings', 'goal'],
    builder: (context, t) => GoalTool(t),
  ),
  AppTool(
    id: 'uyg-harclik-takibi',
    title: kFinTitle['uyg-harclik-takibi']!,
    tagline: kFinTag['uyg-harclik-takibi']!,
    icon: Icons.child_care_rounded,
    color: const Color(0xFFEC407A),
    category: 'track',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['allowance', 'kids'],
    builder: (context, t) => AllowanceTool(t),
  ),
  AppTool(
    id: 'uyg-birim-fiyat-karsilastirma',
    title: kFinTitle['uyg-birim-fiyat-karsilastirma']!,
    tagline: kFinTag['uyg-birim-fiyat-karsilastirma']!,
    icon: Icons.compare_arrows_rounded,
    color: const Color(0xFF8D6E63),
    category: 'shop',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['unit price', 'kg', 'L'],
    builder: (context, t) => UnitPriceTool(t),
  ),
  AppTool(
    id: 'uyg-taksit-hesaplayici',
    title: kFinTitle['uyg-taksit-hesaplayici']!,
    tagline: kFinTag['uyg-taksit-hesaplayici']!,
    icon: Icons.calendar_view_month_rounded,
    color: const Color(0xFF29B6F6),
    category: 'loan',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['installment', 'peşin'],
    builder: (context, t) => InstallmentTool(t),
  ),
  AppTool(
    id: 'uyg-kredi-karti-borc-planlayici',
    title: kFinTitle['uyg-kredi-karti-borc-planlayici']!,
    tagline: kFinTag['uyg-kredi-karti-borc-planlayici']!,
    icon: Icons.credit_card_rounded,
    color: const Color(0xFF7E57C2),
    category: 'loan',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['credit card', 'asgari'],
    builder: (context, t) => CardTool(t),
  ),
  AppTool(
    id: 'uyg-kira-artis-hesaplayici',
    title: kFinTitle['uyg-kira-artis-hesaplayici']!,
    tagline: kFinTag['uyg-kira-artis-hesaplayici']!,
    icon: Icons.home_work_rounded,
    color: const Color(0xFF26C6DA),
    category: 'tax',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['rent', 'tüfe', 'cpi'],
    builder: (context, t) => RentTool(t),
  ),
  AppTool(
    id: 'uyg-enflasyon-hesaplayici',
    title: kFinTitle['uyg-enflasyon-hesaplayici']!,
    tagline: kFinTag['uyg-enflasyon-hesaplayici']!,
    icon: Icons.price_change_rounded,
    color: const Color(0xFFE57373),
    category: 'tax',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['inflation', 'tüfe', 'cpi'],
    builder: (context, t) => InflationTool(t),
  ),
  AppTool(
    id: 'uyg-gelir-vergisi-hesaplayici',
    title: kFinTitle['uyg-gelir-vergisi-hesaplayici']!,
    tagline: kFinTag['uyg-gelir-vergisi-hesaplayici']!,
    icon: Icons.request_page_rounded,
    color: const Color(0xFF78909C),
    category: 'tax',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['tax', 'vergi', 'dilim'],
    builder: (context, t) => IncomeTaxTool(t),
  ),
  AppTool(
    id: 'uyg-zekat-hesaplayici',
    title: kFinTitle['uyg-zekat-hesaplayici']!,
    tagline: kFinTag['uyg-zekat-hesaplayici']!,
    icon: Icons.volunteer_activism_rounded,
    color: const Color(0xFF9CCC65),
    category: 'tax',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['zakat', 'nisap', 'nisab'],
    builder: (context, t) => ZakatTool(t),
  ),
  AppTool(
    id: 'uyg-konut-kredisi-hesaplayici',
    title: kFinTitle['uyg-konut-kredisi-hesaplayici']!,
    tagline: kFinTag['uyg-konut-kredisi-hesaplayici']!,
    icon: Icons.house_rounded,
    color: const Color(0xFF4DB6AC),
    category: 'loan',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['mortgage', 'konut', 'ev', 'amortization', 'prepayment'],
    builder: (context, t) => MortgageTool(t),
  ),
  AppTool(
    id: 'uyg-emeklilik-hesaplayici',
    title: kFinTitle['uyg-emeklilik-hesaplayici']!,
    tagline: kFinTag['uyg-emeklilik-hesaplayici']!,
    icon: Icons.beach_access_rounded,
    color: const Color(0xFFFFB74D),
    category: 'loan',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['retirement', 'emeklilik', 'pension', 'bes', 'fire'],
    builder: (context, t) => RetirementTool(t),
  ),
  AppTool(
    id: 'uyg-net-varlik-takibi',
    title: kFinTitle['uyg-net-varlik-takibi']!,
    tagline: kFinTag['uyg-net-varlik-takibi']!,
    icon: Icons.diamond_rounded,
    color: const Color(0xFF81C784),
    category: 'track',
    disclaimer: AppDisclaimer.finance,
    keywords: const ['net worth', 'varlık', 'assets', 'debts', 'csv'],
    builder: (context, t) => NetWorthTool(t),
  ),
];

/// Depo adıyla araç (ör. 'uyg-kredi-hesaplayici').
AppTool finansTool(String id) => finansTools.firstWhere((t) => t.id == id);

/// Merkezin başlığı ve kısa açıklaması.
final List<String> finansHubTitle = kFinCat['hub_title']!;
final List<String> finansHubTagline = kFinCat['hub_tag']!;

/// Onaylı merkez tasarımının koyu yeşil, sakin tonu.
const ApprovedHubStyle finansHubStyle = ApprovedHubStyle(
  background: [Color(0xFF14432F), Color(0xFF0C2B1F), Color(0xFF061710)],
  accent: Color(0xFF7BE0A1),
  card: Color(0xFF1E5640),
  play: Color(0xFF2E9E66),
  number: Colors.white,
);

/// Öne çıkanlar.
const List<String> finansFeatured = [
  'uyg-butce-ve-harcama-takibi', 'uyg-kredi-hesaplayici', 'uyg-abonelik-takibi', 'uyg-kira-artis-hesaplayici',
  'uyg-birikim-hedefi', 'uyg-indirim-ve-kdv-hesaplayici', 'uyg-fatura-hatirlatici', 'uyg-gelir-vergisi-hesaplayici',
];

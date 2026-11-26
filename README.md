# finans-motoru

Finans ve Hesaplama ailesinin motoru: 24 aracın gerçek uygulamaları, 33 dilde metinleri ve
merkez görünümü (onaylı oyun merkezi tasarımının koyu yeşil tonu).

- Çatı: `studio_core/apps` (AppTool, merkez kabuğu, reklam/satın alma, gizlilik, favoriler).
- Her araç kendi ince deposunda (`uyg-*`, Bütçe/Birikim/Borç için yeniden kullanılan `app-009`,
  `app-011`, `app-012`) yayımlanır; merkez uygulama `merkez-finans-ve-hesaplama`.
- Tamamen çevrimdışı. Banka bağlantısı yok; veriler yalnızca cihazda. Kayıt tutan araçlar CSV
  olarak dışa aktarır (panoya kopyalar; mobil/masaüstünde belgeler klasörüne yazar).
- Bütün araçlar `AppDisclaimer.finance` uyarısını gösterir. Uygulama **kredi sunmaz**.
- 4. tur kayıt araçları (`lib/src/shop.dart`, `tools/shop_ui.dart`): **Altın Günü Defteri** (dönüşümlü birikim
  grubu: sıra, takvim, kim ödedi/kim aldı; isteğe bağlı ödülsüz sıra kurası), **Veresiye Defteri** (müşteri cari
  hesabı, limit, hesap dökümü), **Kişisel Sepet Enflasyonu** (kendi fiyat geçmişinden sabit sepet endeksi; resmî
  enflasyon iddiası yok), **Mini Kasa ve Stok** (satış kaydı, stok düşümü, az stok uyarısı, günlük/haftalık/aylık
  özet). Hiçbiri para tutmaz, taşımaz ya da ödeme almaz. Hatırlatma ve döküm metinlerini kullanıcı paylaşım
  menüsüyle (`share_plus`) kendisi gönderir.
- Fatura ve abonelik hatırlatmaları `flutter_local_notifications` ile yerel bildirimdir; kesin alarm
  izni istenmez. Web'de bildirim yoktur, tarihler listede görünür.
- Harçlık takibi **ebeveynler** için bir defterdir; çocuktan veri toplanmaz.
- Konut kredisi hesaplayıcı eşit taksitli plan, aylık/tek seferlik ek ödeme (vade kısalır),
  masraflar ve taksit/gelir oranı gösterir. Emeklilik hesaplayıcı bilgi amaçlı bir projeksiyondur
  (getiri, katkı artışı, enflasyon, çekim süresi; hedef gelire göre gereken katkı); yatırım
  tavsiyesi değildir. Net varlık takibi değerleri kullanıcı girer; her değişiklikte o ayın toplamı
  kaydedilir (en fazla 120 ay), CSV'ye aktarılır.

## Güncellenmesi gereken veriler (`lib/src/core.dart`)

| Veri | Kaynak | Sıklık | Son güncelleme |
|---|---|---|---|
| `kRentCaps` (kira artış sınırı, TÜFE 12 aylık ort.) | TÜİK | Her ay (ayın 3'ü) | 2026-11-03 (Kasım 2026: %31,23) |
| `kCpiAnnual` (yıllık TÜFE) | TÜİK | Her ay / yıl sonu | 2026-11-03 (2026 Ocak–Ekim %27,52) |
| `TaxTariff.wage2026`, `nonWage2026` | GİB (332 Seri No.lu GV Genel Tebliği) | Her yıl | 2026-01-01 |
| `kNisabGrams` | Diyanet (80,18 g altın) | Gerektiğinde | — |

Kredi faizi, KKDF/BSMV, kart faizi ve asgari ödeme oranları kullanıcı tarafından girilir
(varsayılanlar yalnızca örnektir). Kullanıcı vergi dilimlerini ve kira oranını ekranda değiştirebilir.

Metinler `proto/apps/finans_titles.py` ve `finans_labels.py` dosyalarından
`proto/apps/finans/mkengine.py` ile üretilir (`lib/src/tx.dart`, `lib/src/registry.dart`).

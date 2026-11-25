# finans-motoru

Finans ve Hesaplama ailesinin motoru: 17 aracın gerçek uygulamaları, 33 dilde metinleri ve
merkez görünümü (onaylı oyun merkezi tasarımının koyu yeşil tonu).

- Çatı: `studio_core/apps` (AppTool, merkez kabuğu, reklam/satın alma, gizlilik, favoriler).
- Her araç kendi ince deposunda (`uyg-*`, Bütçe/Birikim/Borç için yeniden kullanılan `app-009`,
  `app-011`, `app-012`) yayımlanır; merkez uygulama `merkez-finans-ve-hesaplama`.
- Tamamen çevrimdışı. Banka bağlantısı yok; veriler yalnızca cihazda. Kayıt tutan araçlar CSV
  olarak dışa aktarır (panoya kopyalar; mobil/masaüstünde belgeler klasörüne yazar).
- Bütün araçlar `AppDisclaimer.finance` uyarısını gösterir. Uygulama **kredi sunmaz**.
- Fatura ve abonelik hatırlatmaları `flutter_local_notifications` ile yerel bildirimdir; kesin alarm
  izni istenmez. Web'de bildirim yoktur, tarihler listede görünür.
- Harçlık takibi **ebeveynler** için bir defterdir; çocuktan veri toplanmaz.

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

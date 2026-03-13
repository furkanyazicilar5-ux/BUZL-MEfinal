import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'error_codes.dart';
import 'app_info.dart';

/// SalesData — satış, iade ve stok yönetimi
///
/// Firestore yapısı (ilgili alanlar):
///   inventory.smallCups  : int   — küçük bardak adedi
///   inventory.largeCups  : int   — büyük bardak adedi
///   levels.lemon         : int   — limon içecek seviyesi (mL)
///   levels.orange        : int   — portakal içecek seviyesi (mL)
///   levels.liquid        : int   — LEGACY toplam seviye (geriye uyumluluk)
///
/// Her satışta:
///   - Küçük bardak: 1 küçük bardak + 300 mL içecek düşür (ilgili türden)
///   - Büyük bardak: 1 büyük bardak + 400 mL içecek düşür (ilgili türden)
///
/// İçecek tam dolu: 19 000 mL (hem Limon hem Portakal)
class SalesData {
  static final SalesData instance = SalesData._internal();
  SalesData._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String machineId = kMachineId;
  String? lastSaleCupType;

  // ─── Küçük bardak porsiyon hacmi (mL) ──────────────────────────────────
  static const int kSmallMl = 300;
  // ─── Büyük bardak porsiyon hacmi (mL) ──────────────────────────────────
  static const int kLargeMl = 400;

  Future<void> _ensureDailyLog(String day) async {
    final logRef = _db
        .collection('machines')
        .doc(machineId)
        .collection('profit_logs')
        .doc(day);

    await logRef.set({
      'timestamp': FieldValue.serverTimestamp(),
      'totalProfit': 0.0,
      'smallSold': 0,
      'largeSold': 0,
      'smallTl': 0.0,
      'largeTl': 0.0,
      'refunds': {
        'total': 0,
        'amountTl': 0.0,
        'amountMl': 0,
        'details': {'overfreeze': 0, 'cupDrop': 0, 'other': 0},
      },
    }, SetOptions(merge: true));
  }

  /// Küçük bardak satışı (eski API, geriye uyumluluk)
  Future<void> sellSmall({required double priceTl}) async {
    await sellDrink(title: 'smallCup', volume: 'small', priceTl: priceTl);
  }

  /// Büyük bardak satışı (eski API, geriye uyumluluk)
  Future<void> sellLarge({required double priceTl}) async {
    await sellDrink(title: 'largeCup', volume: 'large', priceTl: priceTl);
  }

  /// Ana satış metodu.
  ///
  /// [title]   → 'Limon' | 'Portakal' (içecek türü; 'smallCup'/'largeCup' legacy de kabul edilir)
  /// [volume]  → 'small' | 'large' | '300 ml' | '400 ml' vb.  (bardak boyutu)
  /// [drinkCode] → 'LEMON' | 'ORANGE'  (opsiyonel, title'dan çıkarılır)
  ///
  /// Firestore transaction içinde:
  ///   1) Bardak sayısını 1 azalt (boyuta göre küçük/büyük)
  ///   2) İlgili içecek seviyesini (levels.lemon veya levels.orange) ml kadar azalt
  ///   3) Legacy levels.liquid alanını da güncelle (toplam)
  ///   4) Satış ve kar kayıtlarını güncelle
  Future<void> sellDrink({
    required String title,
    required String volume,
    required double priceTl,
    String? drinkCode, // 'LEMON' | 'ORANGE'
  }) async {
    // ─── Bardak boyutunu belirle ───────────────────────────────────────────
    final isSmall = _isSmallCup(volume);
    lastSaleCupType = isSmall ? 'small' : 'large';
    final ml = isSmall ? kSmallMl : kLargeMl;

    // ─── İçecek türünü belirle ─────────────────────────────────────────────
    // drinkCode yoksa title'dan çıkar
    final drink = drinkCode ?? _drinkCodeFromTitle(title);
    final liquidKey = _liquidKeyForDrink(drink); // 'lemon' | 'orange'

    final now = DateTime.now().toLocal();
    final day = DateFormat('yyyy-MM-dd').format(now);
    final machineRef = _db.collection('machines').doc(machineId);
    final logRef = machineRef.collection('profit_logs').doc(day);

    await _ensureDailyLog(day);

    await _db.runTransaction((tx) async {
      // ── OKUMALAR ──────────────────────────────────────────────────────────
      final mSnap = await tx.get(machineRef);
      final lSnap = await tx.get(logRef);

      final m     = mSnap.data() ?? {};
      final inv   = Map<String, dynamic>.from(m['inventory']    ?? {});
      final lv    = Map<String, dynamic>.from(m['levels']       ?? {});
      final dp    = Map<String, dynamic>.from(m['daily_profit'] ??
          {'current_day': day, 'profit_today': 0.0});
      final sales = Map<String, dynamic>.from(m['sales']        ??
          {'smallSold': 0, 'largeSold': 0, 'smallTl': 0.0, 'largeTl': 0.0});
      final l     = lSnap.data() ?? {};

      // ── STOK KONTROL ──────────────────────────────────────────────────────
      final cupField = isSmall ? 'smallCups' : 'largeCups';
      final cups     = (inv[cupField] ?? 0) as int;
      if (cups <= 0) throw StateError('Bardak stoku tükendi ($cupField).');

      // İçecek seviyesi — önce ayrı alan, yoksa legacy liquid
      final currentLiquid = (lv[liquidKey] ?? lv['liquid'] ?? 0) as int;
      if (currentLiquid < ml) {
        throw StateError('İçecek seviyesi yetersiz ($liquidKey: $currentLiquid mL < $ml mL).');
      }

      // ── HESAPLA ───────────────────────────────────────────────────────────
      inv[cupField] = cups - 1;

      // Ayrı içecek alanını düşür
      lv[liquidKey] = currentLiquid - ml;

      // Legacy levels.liquid'i güncelle (lemon + orange toplamı)
      final otherKey    = liquidKey == 'lemon' ? 'orange' : 'lemon';
      final otherLiquid = (lv[otherKey] ?? lv['liquid'] ?? 0) as int;
      lv['liquid']      = (lv[liquidKey] as int) + otherLiquid;

      dp['current_day']   = day;
      dp['profit_today']  = (dp['profit_today'] ?? 0.0) + priceTl;

      if (isSmall) {
        sales['smallSold'] = (sales['smallSold'] ?? 0) + 1;
        sales['smallTl']   = (sales['smallTl']   ?? 0.0) + priceTl;
      } else {
        sales['largeSold'] = (sales['largeSold'] ?? 0) + 1;
        sales['largeTl']   = (sales['largeTl']   ?? 0.0) + priceTl;
      }

      // ── YAZMALAR ──────────────────────────────────────────────────────────
      tx.update(machineRef, {
        'inventory':    inv,
        'levels':       lv,
        'daily_profit': dp,
        'profit_total': FieldValue.increment(priceTl),
        'sales':        sales,
      });

      final lSales = isSmall
          ? {
        'smallSold': (l['smallSold'] ?? 0) + 1,
        'smallTl':   (l['smallTl']   ?? 0.0) + priceTl,
      }
          : {
        'largeSold': (l['largeSold'] ?? 0) + 1,
        'largeTl':   (l['largeTl']   ?? 0.0) + priceTl,
      };
      tx.set(logRef, lSales, SetOptions(merge: true));
    });
  }

  /// İade kaydı
  Future<void> logRefund({
    required double amountTl,
    required int    amountMl,
    required String errorCode,
    required String cupType,
  }) async {
    if (!RefundErrorCodes.isValid(errorCode)) {
      throw ArgumentError('Geçersiz hata kodu: $errorCode');
    }

    final tmpRef  = await _db.collection('meta').add({'now': FieldValue.serverTimestamp()});
    final snap    = await tmpRef.get();
    await tmpRef.delete();
    final serverNow = (snap['now'] as Timestamp).toDate().toLocal();
    final day       = DateFormat('yyyy-MM-dd').format(serverNow);
    final machineRef = _db.collection('machines').doc(machineId);
    final logRef     = machineRef.collection('profit_logs').doc(day);

    await _ensureDailyLog(day);

    await _db.runTransaction((tx) async {
      final logSnap = await tx.get(logRef);
      final mSnap   = await tx.get(machineRef);

      final ldata = logSnap.data() ?? {};
      final mdata = mSnap.data()  ?? {};

      final lrefunds = Map<String, dynamic>.from(ldata['refunds'] ?? {});
      final ldetails = Map<String, dynamic>.from(lrefunds['details'] ?? {});
      lrefunds['total']    = (lrefunds['total']    ?? 0) + 1;
      lrefunds['amountTl'] = (lrefunds['amountTl'] ?? 0.0) + amountTl;
      lrefunds['amountMl'] = (lrefunds['amountMl'] ?? 0) + amountMl;
      ldetails[errorCode]  = (ldetails[errorCode]  ?? 0) + 1;
      lrefunds['details']  = ldetails;
      tx.set(logRef, {'refunds': lrefunds}, SetOptions(merge: true));

      final mrefunds = Map<String, dynamic>.from(mdata['refunds'] ?? {});
      final mdetails = Map<String, dynamic>.from(
        mrefunds['details'] ??
            {'overfreeze': 0, 'cupDrop': 0, 'other': 0},
      );
      mrefunds['total']    = (mrefunds['total']    ?? 0) + 1;
      mrefunds['amountTl'] = (mrefunds['amountTl'] ?? 0.0) + amountTl;
      mrefunds['amountMl'] = (mrefunds['amountMl'] ?? 0) + amountMl;
      mdetails[errorCode]  = (mdetails[errorCode]  ?? 0) + 1;
      mrefunds['details']  = mdetails;
      tx.set(machineRef, {'refunds': mrefunds}, SetOptions(merge: true));
    });

    await machineRef
        .collection('profit_logs')
        .doc('refund_logs')
        .collection(day)
        .add({
      'timestamp': Timestamp.fromDate(serverNow),
      'cupType':   cupType,
      'errorCode': errorCode,
      'amountTl':  amountTl,
      'amountMl':  amountMl,
    });
  }

  // ─── YARDIMCI ──────────────────────────────────────────────────────────────

  /// volume / title'dan küçük bardak mı belirle
  bool _isSmallCup(String s) {
    final low = s.toLowerCase();
    return low.contains('small') ||
        low.contains('küçük') ||
        low.contains('300');
  }

  /// title → drinkCode
  String _drinkCodeFromTitle(String title) {
    final t = title.toLowerCase();
    if (t.contains('limon') || t.contains('lemon')) return 'LEMON';
    if (t.contains('portakal') || t.contains('orange')) return 'ORANGE';
    return 'LEMON'; // varsayılan
  }

  /// drinkCode → Firestore levels alanı
  String _liquidKeyForDrink(String drinkCode) {
    return drinkCode == 'ORANGE' ? 'orange' : 'lemon';
  }
}
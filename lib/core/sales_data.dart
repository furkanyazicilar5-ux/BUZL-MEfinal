import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'error_codes.dart';
import 'app_info.dart';

class SalesData {
  static final SalesData instance = SalesData._internal();
  SalesData._internal();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String machineId = kMachineId;
  String? lastSaleCupType;

  Future<void> _ensureDailyLog(String day) async {
    final logRef = _db.collection('machines').doc(machineId)
        .collection('profit_logs').doc(day);

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

  /// Küçük bardak satışı
  Future<void> sellSmall({required double priceTl}) async {
    lastSaleCupType = 'small';
    final now = DateTime.now().toLocal();
    final day = DateFormat('yyyy-MM-dd').format(now);
    final machineRef = _db.collection('machines').doc(machineId);
    final logRef = machineRef.collection('profit_logs').doc(day);

    await _ensureDailyLog(day);

    await _db.runTransaction((tx) async {
      final mSnap = await tx.get(machineRef);
      final m = (mSnap.data() ?? {});
      final inv = Map<String, dynamic>.from(m['inventory'] ?? {});
      final lv = Map<String, dynamic>.from(m['levels'] ?? {});
      final dp = Map<String, dynamic>.from(m['daily_profit'] ?? {'current_day': day, 'profit_today': 0.0});
      final sales = Map<String, dynamic>.from(m['sales'] ?? {'smallSold': 0, 'largeSold': 0, 'smallTl': 0.0, 'largeTl': 0.0});

      final cups = (inv['smallCups'] ?? 0) as int;
      final liquid = (lv['liquid'] ?? 0) as int;
      if (cups <= 0 || liquid < 300) throw StateError('Yetersiz stok.');

      inv['smallCups'] = cups - 1;
      lv['liquid'] = liquid - 300;
      dp['current_day'] = day;
      dp['profit_today'] = (dp['profit_today'] ?? 0.0) + priceTl;
      sales['smallSold'] = (sales['smallSold'] ?? 0) + 1;
      sales['smallTl'] = (sales['smallTl'] ?? 0.0) + priceTl;

      tx.update(machineRef, {
        'inventory': inv,
        'levels': lv,
        'daily_profit': dp,
        'profit_total': FieldValue.increment(priceTl),
        'sales': sales,
      });

      final lSnap = await tx.get(logRef);
      final l = (lSnap.data() ?? {});
      final lSales = {
        'smallSold': (l['smallSold'] ?? 0) + 1,
        'smallTl': (l['smallTl'] ?? 0.0) + priceTl,
      };
      tx.set(logRef, lSales, SetOptions(merge: true));
    });
  }

  /// Büyük bardak satışı
  Future<void> sellLarge({required double priceTl}) async {
    lastSaleCupType = 'large';
    final now = DateTime.now().toLocal();
    final day = DateFormat('yyyy-MM-dd').format(now);
    final machineRef = _db.collection('machines').doc(machineId);
    final logRef = machineRef.collection('profit_logs').doc(day);

    await _ensureDailyLog(day);

    await _db.runTransaction((tx) async {
      final mSnap = await tx.get(machineRef);
      final m = (mSnap.data() ?? {});
      final inv = Map<String, dynamic>.from(m['inventory'] ?? {});
      final lv = Map<String, dynamic>.from(m['levels'] ?? {});
      final dp = Map<String, dynamic>.from(m['daily_profit'] ?? {'current_day': day, 'profit_today': 0.0});
      final sales = Map<String, dynamic>.from(m['sales'] ?? {'smallSold': 0, 'largeSold': 0, 'smallTl': 0.0, 'largeTl': 0.0});

      final cups = (inv['largeCups'] ?? 0) as int;
      final liquid = (lv['liquid'] ?? 0) as int;
      if (cups <= 0 || liquid < 400) throw StateError('Yetersiz stok.');

      inv['largeCups'] = cups - 1;
      lv['liquid'] = liquid - 400;
      dp['current_day'] = day;
      dp['profit_today'] = (dp['profit_today'] ?? 0.0) + priceTl;
      sales['largeSold'] = (sales['largeSold'] ?? 0) + 1;
      sales['largeTl'] = (sales['largeTl'] ?? 0.0) + priceTl;

      tx.update(machineRef, {
        'inventory': inv,
        'levels': lv,
        'daily_profit': dp,
        'profit_total': FieldValue.increment(priceTl),
        'sales': sales,
      });

      final lSnap = await tx.get(logRef);
      final l = (lSnap.data() ?? {});
      final lSales = {
        'largeSold': (l['largeSold'] ?? 0) + 1,
        'largeTl': (l['largeTl'] ?? 0.0) + priceTl,
      };
      tx.set(logRef, lSales, SetOptions(merge: true));
    });
  }

  /// İade kaydı
  Future<void> logRefund({
    required double amountTl,
    required int amountMl,
    required String errorCode,
    required String cupType,
  }) async {
    if (!RefundErrorCodes.isValid(errorCode)) {
      throw ArgumentError('Geçersiz hata kodu: $errorCode');
    }
    final finalCupType = cupType;

    final tmpRef = await _db.collection('meta').add({'now': FieldValue.serverTimestamp()});
    final snap = await tmpRef.get();
    await tmpRef.delete();
    final serverNow = (snap['now'] as Timestamp).toDate().toLocal();
    final day = DateFormat('yyyy-MM-dd').format(serverNow);
    final machineRef = _db.collection('machines').doc(machineId);
    final logRef = machineRef.collection('profit_logs').doc(day);

    await _ensureDailyLog(day);

    await _db.runTransaction((tx) async {
      final logSnap = await tx.get(logRef);
      final mSnap = await tx.get(machineRef);

      final ldata = (logSnap.data() ?? {});
      final mdata = (mSnap.data() ?? {});

      final lrefunds = Map<String, dynamic>.from(ldata['refunds'] ?? {});
      final ldetails = Map<String, dynamic>.from(lrefunds['details'] ?? {});
      lrefunds['total'] = (lrefunds['total'] ?? 0) + 1;
      lrefunds['amountTl'] = (lrefunds['amountTl'] ?? 0.0) + amountTl;
      lrefunds['amountMl'] = (lrefunds['amountMl'] ?? 0) + amountMl;
      ldetails[errorCode] = (ldetails[errorCode] ?? 0) + 1;
      lrefunds['details'] = ldetails;
      tx.set(logRef, {'refunds': lrefunds}, SetOptions(merge: true));

      final mrefunds = Map<String, dynamic>.from(mdata['refunds'] ?? {});
      final mdetails = Map<String, dynamic>.from(
        (mrefunds['details'] ?? {'overfreeze': 0, 'cupDrop': 0, 'other': 0}),
      );
      mrefunds['total'] = (mrefunds['total'] ?? 0) + 1;
      mrefunds['amountTl'] = (mrefunds['amountTl'] ?? 0.0) + amountTl;
      mrefunds['amountMl'] = (mrefunds['amountMl'] ?? 0) + amountMl;
      mdetails[errorCode] = (mdetails[errorCode] ?? 0) + 1;
      mrefunds['details'] = mdetails;
      tx.set(machineRef, {'refunds': mrefunds}, SetOptions(merge: true));
    });

    await machineRef
        .collection('profit_logs')
        .doc('refund_logs')
        .collection(day)
        .add({
          'timestamp': Timestamp.fromDate(serverNow),
          'cupType': finalCupType,
          'errorCode': errorCode,
          'amountTl': amountTl,
          'amountMl': amountMl,
        });
  }

  Future<void> sellDrink({
    required String title,
    required String volume,
    required double priceTl,
  }) async {
    final isSmall = title == 'smallCup';
    lastSaleCupType = isSmall ? 'small' : 'large';
    final now = DateTime.now().toLocal();
    final day = DateFormat('yyyy-MM-dd').format(now);
    final machineRef = _db.collection('machines').doc(machineId);
    final logRef = machineRef.collection('profit_logs').doc(day);

    await _ensureDailyLog(day);

    await _db.runTransaction((tx) async {
      // 1️⃣ TÜM OKUMALAR EN BAŞTA
      final mSnap = await tx.get(machineRef);
      final lSnap = await tx.get(logRef);

      final m = (mSnap.data() ?? {});
      final inv = Map<String, dynamic>.from(m['inventory'] ?? {});
      final lv = Map<String, dynamic>.from(m['levels'] ?? {});
      final dp = Map<String, dynamic>.from(m['daily_profit'] ?? {'current_day': day, 'profit_today': 0.0});
      final sales = Map<String, dynamic>.from(m['sales'] ?? {'smallSold': 0, 'largeSold': 0, 'smallTl': 0.0, 'largeTl': 0.0});
      final l = (lSnap.data() ?? {});

      // 2️⃣ İŞLEMLER
      if (isSmall) {
        final cups = (inv['smallCups'] ?? 0) as int;
        final liquid = (lv['liquid'] ?? 0) as int;
        if (cups <= 0 || liquid < 300) throw StateError('Yetersiz stok.');
        inv['smallCups'] = cups - 1;
        lv['liquid'] = liquid - 300;
        dp['current_day'] = day;
        dp['profit_today'] = (dp['profit_today'] ?? 0.0) + priceTl;
        sales['smallSold'] = (sales['smallSold'] ?? 0) + 1;
        sales['smallTl'] = (sales['smallTl'] ?? 0.0) + priceTl;
      } else {
        final cups = (inv['largeCups'] ?? 0) as int;
        final liquid = (lv['liquid'] ?? 0) as int;
        if (cups <= 0 || liquid < 400) throw StateError('Yetersiz stok.');
        inv['largeCups'] = cups - 1;
        lv['liquid'] = liquid - 400;
        dp['current_day'] = day;
        dp['profit_today'] = (dp['profit_today'] ?? 0.0) + priceTl;
        sales['largeSold'] = (sales['largeSold'] ?? 0) + 1;
        sales['largeTl'] = (sales['largeTl'] ?? 0.0) + priceTl;
      }

      // 3️⃣ TÜM YAZMALAR EN SON
      tx.update(machineRef, {
        'inventory': inv,
        'levels': lv,
        'daily_profit': dp,
        'profit_total': FieldValue.increment(priceTl),
        'sales': sales,
      });

      if (isSmall) {
        final lSales = {
          'smallSold': (l['smallSold'] ?? 0) + 1,
          'smallTl': (l['smallTl'] ?? 0.0) + priceTl,
        };
        tx.set(logRef, lSales, SetOptions(merge: true));
      } else {
        final lSales = {
          'largeSold': (l['largeSold'] ?? 0) + 1,
          'largeTl': (l['largeTl'] ?? 0.0) + priceTl,
        };
        tx.set(logRef, lSales, SetOptions(merge: true));
      }
    });
  }


}
// SPDX-License-Identifier: MIT
// integration_entry.dart — Buzlime sipariş başlatma ve servis entegrasyon noktası
//
// DEĞİŞİKLİKLİK:
//   - startBuzlimeOrder() imzasından `priceKurus` parametresi tamamen kaldırıldı.
//     Fiyat ve ödeme otoritesi yalnızca MCU/MDB'dedir; uygulama fiyat göndermez.
//   - BuzlimeOrder constructor çağrısından priceKurus alanı silindi.
//   - Dönen durum string'leri ve hata mantığı korundu.

import 'device_controller.dart';

/// Uygulama boyunca tek bir DeviceController örneği kullanılır (singleton).
final DeviceController _dev = DeviceController();

/// Singleton DeviceController erişimi.
DeviceController getDeviceController() => _dev;

/// USB + MCU bağlantısını test eder (connect() içinde WATCHDOG gönderilir).
Future<bool> ensureDeviceConnected() async => _dev.connect();

/// Siparişi başlatır.
///
/// [drinkCode] : 'LEMON' | 'ORANGE'
/// [sizeMl]    : 300 | 400
///
/// Dönen durumlar:
///   'started' — Sipariş MCU tarafından kabul edildi; event bekleniyor.
///   'error'   — Bağlantı hatası veya MCU reddi; SalesClosedPage'e yönlendirin.
Future<String> startBuzlimeOrder({
  required String drinkCode,
  required int sizeMl,
}) async {
  // 1) Bağlan (zaten bağlıysa hızlıca döner)
  final ok = await _dev.connect();
  if (!ok) return 'error';

  // 2) Sipariş oluştur ve gönder — fiyat bilgisi YOK (MCU/MDB yetkisinde)
  try {
    await _dev.startOrder(
      BuzlimeOrder(drinkCode: drinkCode, sizeMl: sizeMl),
    );
    return 'started';
  } catch (_) {
    // MCU meşgul, reddetti veya format hatası
    return 'error';
  }
}

/// MCU'yu RESET komutu ile sıfırlar.
///
/// Satış kapalı durumundan çıkmak için servis personeli çağırır.
///
/// Dönen durumlar:
///   'reset'  — RESET başarılı.
///   'no_usb' — USB/MCU bağlanamadı.
///   'error'  — RESET komutu başarısız.
Future<String> resetBuzlimeDevice() async {
  final ok = await _dev.connect();
  if (!ok) return 'no_usb';
  try {
    await _dev.reset();
    return 'reset';
  } catch (_) {
    return 'error';
  }
}

/// Uygulama kapanırken ya da cihazı kesin kapatmak istediğinde çağrılır.
Future<void> disposeDevice() async => _dev.close();
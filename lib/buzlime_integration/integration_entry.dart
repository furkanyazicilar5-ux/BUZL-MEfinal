// SPDX-License-Identifier: MIT
// integration_entry.dart — Buzlime sipariş başlatma ve servis entegrasyon noktası
// Bu revizyon PDF gereksinimlerine uygun olarak RESET fonksiyonunu ekler.

import 'package:flutter/material.dart';

import 'device_controller.dart';

/// Uygulama boyunca tek bir DeviceController örneği kullanıyoruz.
final DeviceController _dev = DeviceController();

DeviceController getDeviceController() => _dev;

/// USB + MCU hazır mı? (connect içinde WATCHDOG var)
Future<bool> ensureDeviceConnected() async {
  return _dev.connect();
}

/// Siparişi başlatır.
///
/// [drinkCode]: 'LEMON' | 'ORANGE'
/// [sizeMl]: 300 | 400
/// [priceKurus]: örn 4000 (40 TL) — MCU'da otorite olduğu için opsiyoneldir.
///
/// Dönen durumlar:
/// - 'no_usb' : USB/MCU bağlanamadı (satış yok, ana menüye dön)
/// - 'started' : Sipariş kabul edildi (bundan sonra event beklenir)
/// - 'error' : Başlatma hatası (SalesClosedPage'e gideceğiz)
Future<String> startBuzlimeOrder({
  required String drinkCode,
  required int sizeMl,
  int? priceKurus,
}) async {
  // 1) USB + MCU bağlan (connect içinde WATCHDOG atılıyor)
  final ok = await _dev.connect();
  if (!ok) {
    // MCU yoksa da "hata" kabul ediyoruz => SalesClosed
    return 'error';
  }
  // 2) Sipariş oluştur ve başlat
  try {
    final order = BuzlimeOrder(
      drinkCode: drinkCode,
      sizeMl: sizeMl,
      priceKurus: priceKurus,
    );
    await _dev.startOrder(order);
    return 'started';
  } catch (_) {
    // Buraya düştüyse:
    // - MCU busy olabilir
    // - START_ORDER reddedilmiş olabilir
    // - cevap formatı bozuk olabilir
    return 'error';
  }
}

/// Cihazı RESET komutu ile sıfırlar.
///
/// Bu fonksiyon, servis personeli tarafından satış kapalı durumu oluştuğunda
/// çağrılmalıdır. MCU'ya RESET komutunu yollar ve durumun reset edildiğini
/// bildirir. Başarılı olursa 'reset', bağlantı yoksa 'no_usb', hata
/// oluşursa 'error' döner.
Future<String> resetBuzlimeDevice() async {
  // Cihaza bağlanmayı dene; halihazırda bağlıysa connect() true döndürür.
  final ok = await _dev.connect();
  if (!ok) {
    return 'no_usb';
  }
  try {
    await _dev.reset();
    return 'reset';
  } catch (_) {
    return 'error';
  }
}

/// Uygulama kapanırken veya kesin kapatmak istersen.
Future<void> disposeDevice() async {
  await _dev.close();
}

// SPDX-License-Identifier: MIT
//
// integration_entry.dart — Buzlime sipariş başlatma giriş noktası
// Flutter minimum:
// - connect() ile USB+MCU var mı kontrol
// - startOrder() ile siparişi başlat
// Bundan sonrası Preparing/Processing sayfalarında event'lerle yürür.

import 'package:flutter/material.dart';

import 'device_controller.dart';

final DeviceController _dev = DeviceController();

DeviceController getDeviceController() => _dev;

/// USB + MCU hazır mı? (connect içinde WATCHDOG var)
Future<bool> ensureDeviceConnected() async {
  return _dev.connect();
}

/// Siparişi başlatır.
/// drinkCode: 'LEMON' | 'ORANGE'
/// sizeMl: 300 | 400
/// priceKurus: örn 4000 (40 TL)
///
/// Dönen durumlar:
/// - 'no_usb'  : USB/MCU bağlanamadı (satış yok, ana menüye dön)
/// - 'started' : Sipariş kabul edildi (bundan sonra event beklenir)
/// - 'error'   : Başlatma hatası (SalesClosedPage'e gideceğiz)
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

/// Uygulama kapanırken veya kesin kapatmak istersen.
Future<void> disposeDevice() async {
  await _dev.close();
}

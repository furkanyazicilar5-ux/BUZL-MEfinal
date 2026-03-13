// SPDX-License-Identifier: MIT
// models.dart
//
// DEĞİŞİKLİKLER:
//   - V1 Cmd sınıfı tamamen silindi (donanım test artığı, hiçbir V2 kodu kullanmıyor).
//   - Json typedef korundu (protocol_v2.dart + diğerleri kullanıyor).
//   - Telemetry: priceKurus, paidKurus, remainingKurus, changeKurus korundu;
//     bu alanlar MCU'dan gelen ödeme bilgilerini pasif olarak yansıtır
//     (uygulama bu değerleri göndermez, sadece okur — otorite MCU/MDB'de).
//   - copy() metodu güncellendi.

typedef Json = Map<String, dynamic>;

// ─── V1 Cmd sınıfı KALDIRILDI ─────────────────────────────────────────────────
// Eski donanım test protokolü (v=1) projede artık kullanılmıyor.
// Tüm komutlar protocol_v2.dart üzerinden ProtocolClient.sendCmd() ile gönderilir.
// ─────────────────────────────────────────────────────────────────────────────────

/// UI tarafında gösterim ve teşhis için telemetri modeli.
///
/// ÖNEMLI: Bu model yalnızca MCU'dan gelen verileri yansıtır.
/// Uygulama tarafı hiçbir zaman fiyat veya ödeme verisi göndermez;
/// tüm fiyat/ödeme otoritesi MCU/MDB'ye aittir.
class Telemetry {
  // ── Hata bilgisi ─────────────────────────────────────────────────────────────
  String? lastError;
  String? lastErrorCode;
  String? lastRecovery;

  // ── Cihaz kimliği ─────────────────────────────────────────────────────────────
  String? deviceId;
  String? fwVersion;

  // ── Sipariş durumu (MCU'dan gelir, v2) ────────────────────────────────────────
  int?    orderId;
  String? state;    // WAIT_PAYMENT | PAYMENT_OK | DISPENSE_CUP | FILLING | ...
  double? progress; // 0.0 – 1.0 (MCU iletir, uygulama okur)

  // ── Ödeme bilgisi (MCU/MDB'den pasif olarak okunur, uygulama göndermez) ────────
  int? priceKurus;     // MCU'nun belirlediği fiyat (kuruş)
  int? paidKurus;      // Ödenen miktar
  int? remainingKurus; // Kalan miktar
  int? changeKurus;    // Para üstü

  /// Derin kopya — telemetryStream'e gönderilirken referans paylaşımını önler.
  /// Dinleyici eski snapshot'ı değişmez biçimde tutabilir.
  Telemetry copy() {
    return Telemetry()
      ..lastError       = lastError
      ..lastErrorCode   = lastErrorCode
      ..lastRecovery    = lastRecovery
      ..deviceId        = deviceId
      ..fwVersion       = fwVersion
      ..orderId         = orderId
      ..state           = state
      ..progress        = progress
      ..priceKurus      = priceKurus
      ..paidKurus       = paidKurus
      ..remainingKurus  = remainingKurus
      ..changeKurus     = changeKurus;
  }
}
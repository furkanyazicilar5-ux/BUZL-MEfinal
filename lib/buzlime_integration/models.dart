// SPDX-License-Identifier: MIT
//
// models.dart — Ortak modeller
//
// Not: Bu dosya, eski (v1) komut kuyruğu + yeni (v2) sipariş protokolü için
// minimum ortak veri tiplerini içerir.

typedef Json = Map<String, dynamic>;

/// (Legacy) Basit komut formatı (v=1).
/// Bazı test/diagnostic akışlarında hâlâ kullanılabilir.
class Cmd {
  final String type; // 'cmd' | 'read'
  final String name; // M1/M2/M3/... | RELAY | TEMP | TOF
  final String? dir; // 'F' | 'B'
  final Json? data;
  final String? state; // 'ON' | 'OFF'
  final String id;

  Cmd({
    required this.type,
    required this.name,
    this.dir,
    this.data,
    this.state,
    required this.id,
  });

  Json toJson() => <String, dynamic>{
        'v': 1,
        'type': type,
        'name': name,
        if (dir != null) 'dir': dir,
        if (state != null) 'state': state,
        if (data != null) 'data': data,
        'id': id,
      };
}

/// Sipariş akışı için UI tarafında gösterilecek kaba adımlar.

/// UI tarafında gösterim/teşhis için telemetri.
class Telemetry {
  // Genel
  String? lastError;
  String? lastErrorCode;
  String? lastRecovery;

  // Cihaz kimliği
  String? deviceId;
  String? fwVersion;

  // Protokol v2 (sipariş bazlı)
  int? orderId;
  String? state; // WAIT_PAYMENT, PAYMENT_OK, DISPENSE_CUP, ...
  double? progress; // 0.0 - 1.0

  // Ödeme alanı (opsiyonel)
  int? priceKurus;
  int? paidKurus;
  int? remainingKurus;
  int? changeKurus;

  Telemetry copy() {
    final t = Telemetry();
    t.lastError = lastError;
    t.lastErrorCode = lastErrorCode;
    t.lastRecovery = lastRecovery;
    t.deviceId = deviceId;
    t.fwVersion = fwVersion;
    t.orderId = orderId;
    t.state = state;
    t.progress = progress;
    t.priceKurus = priceKurus;
    t.paidKurus = paidKurus;
    t.remainingKurus = remainingKurus;
    t.changeKurus = changeKurus;
    return t;
  }
}

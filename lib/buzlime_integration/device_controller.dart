// SPDX-License-Identifier: MIT
// device_controller.dart — Buzlime USB-CDC protokol istemcisi (Flutter tarafı minimum)
//
// Bu revizyonda "iş" mikrodenetleyicide:
// - MDB ödeme
// - Motor/sensör akışı
// - Hata toparlama
//
// Flutter sadece:
// - START_ORDER gönderir
// - ORDER_STATUS / ORDER_DONE / ORDER_ERROR event'lerini dinler

import 'dart:async';

import '../core/app_info.dart';
import '../core/log_buffer.dart';

import 'models.dart';
import 'protocol_client.dart';
import 'protocol_v2.dart';
import 'usb_cdc.dart';

/// UI'da basit ilerleme için adımlar
enum PrepStep {
  idle,
  waitPayment,
  paymentOk,
  preparing,
  done,
  error,
}

const Map<String, Map<String, String>> kErrorCatalogTr = {
  'DISCONNECTED': {'title': 'Bağlantı yok', 'hint': 'USB bağlantısını kontrol edin.'},
  'PAYMENT_TIMEOUT': {'title': 'Ödeme zaman aşımı', 'hint': 'Ödeme alınamadı.'},
  'PAYMENT_FAILED': {'title': 'Ödeme hatası', 'hint': 'Kart/NFC veya MDB tarafını kontrol edin.'},
  'CUP_EMPTY': {'title': 'Bardak yok', 'hint': 'Bardak stoklarını kontrol edin.'},
  'ICE_EMPTY': {'title': 'Buz yok', 'hint': 'Buz/hazne seviyesini kontrol edin.'},
  'LID_OPEN': {'title': 'Kapak açık', 'hint': 'Servis kapağını kapatın.'},
  'MOTOR_JAM': {'title': 'Motor sıkıştı', 'hint': 'Mekanik sıkışmayı kontrol edin.'},
  'UNKNOWN': {'title': 'Bilinmeyen hata', 'hint': 'Logları kontrol edin.'},
};

class BuzlimeOrder {
  final String drinkCode; // 'LEMON' | 'ORANGE'
  final int sizeMl; // 300 | 400
  final int? priceKurus; // DEPRECATED: fiyat MCU tarafında otorite olmalı (app göndermemeli).

  const BuzlimeOrder({
    required this.drinkCode,
    required this.sizeMl,
    this.priceKurus,
  });
}

class DeviceController {
  final UsbCdcTransport _transport;
  ProtocolClient? _client;

  Timer? _watchdogTimer;
  int _watchdogMiss = 0;

  bool _autoReconnectEnabled = true;
  bool _reconnectLoopRunning = false;
  int _reconnectBackoffMs = 1500;

  final stepStream = StreamController<PrepStep>.broadcast();
  final telemetryStream = StreamController<Telemetry>.broadcast();
  final Telemetry telemetry = Telemetry();

  StreamSubscription<ProtoEvent>? _eventSub;

  bool _connected = false;
  int? _activeOrderId;

  DeviceController({int baudRate = 115200})
      : _transport = UsbCdcTransport(
          // Android tarafında farklı cihazlar olabildiği için "first device" fallback açık.
          vendorIdHint: 0,
          productIdHint: 0,
          baudRate: baudRate,
          autoPickFirstIfNoMatch: true,
        );

  Future<bool> connect() async {
    try {
      LogBuffer.I.add('DeviceController.connect() start');
      await _transport.open();
      _client = ProtocolClient(_transport);

      // Event dinleyicisi (tek kere)
      _eventSub ??= _client!.events.listen(_handleEvent);

      // İlk olarak cihaz durumunu al (fw_version, device_id vs.)
      try {
        final st = await _client!.sendCmd(
          'GET_STATUS',
          payload: {
            'app': {'version': kAppVersion, 'proto': kProtoVersion},
          },
          timeout: const Duration(seconds: 2),
        );
        telemetry.deviceId = asString(st.data?['device_id']) ?? telemetry.deviceId;
        telemetry.fwVersion = asString(st.data?['fw_version']) ?? telemetry.fwVersion;
      } catch (e) {
        // GET_STATUS opsiyonel — MCU desteklemiyorsa problem değil.
        LogBuffer.I.add('GET_STATUS failed: $e');
      }

      // WATCHDOG: gerçekten MCU cevap veriyor mu?
      await _client!.sendCmd(
        'WATCHDOG',
        payload: {'app': {'version': kAppVersion, 'proto': kProtoVersion}},
        timeout: const Duration(seconds: 2),
      );

      _connected = true;
      _watchdogMiss = 0;
      _startWatchdog();

      telemetryStream.add(telemetry);
      LogBuffer.I.add('DeviceController.connect() OK');
      return true;
    } catch (e) {
      LogBuffer.I.add('DeviceController.connect() FAIL: $e');
      _connected = false;
      _stopWatchdog();
      return false;
    }
  }

  Future<void> close() async {
    _stopWatchdog();
    _connected = false;
    LogBuffer.I.add('DeviceController.close()');
    await _eventSub?.cancel();
    _eventSub = null;
    try {
      await _client?.close();
    } catch (_) {}
    _client = null;
    try {
      await _transport.close();
    } catch (_) {}
  }

  bool get isConnected => _connected;

void _startWatchdog() {
  _stopWatchdog();
  _watchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
    if (!_connected || _client == null) return;
    try {
      await _client!.sendCmd(
        'WATCHDOG',
        payload: {'app': {'version': kAppVersion, 'proto': kProtoVersion}},
        timeout: const Duration(seconds: 2),
      );
      _watchdogMiss = 0;
    } catch (e) {
      _watchdogMiss += 1;
      LogBuffer.I.add('WATCHDOG timeout/miss=$_watchdogMiss: $e');
      if (_watchdogMiss >= 3) {
        await _handleDisconnect('WATCHDOG_FAILED');
      }
    }
  });
}

void _stopWatchdog() {
  _watchdogTimer?.cancel();
  _watchdogTimer = null;
}

Future<void> _handleDisconnect(String reason) async {
  if (!_connected) return;
  LogBuffer.I.add('Disconnected: $reason');
  _connected = false;
  _stopWatchdog();
  telemetry.state = 'DISCONNECTED';
  telemetryStream.add(telemetry);

  // Sahada: kullanıcıyı satış kapalı ekranına düşür.
  stepStream.add(PrepStep.error);

  if (_autoReconnectEnabled) {
    _ensureReconnectLoop();
  }
}

void _ensureReconnectLoop() {
  if (_reconnectLoopRunning) return;
  _reconnectLoopRunning = true;
  _reconnectBackoffMs = 1500;

  () async {
    while (!_connected && _autoReconnectEnabled) {
      try {
        LogBuffer.I.add('Reconnect attempt...');
        await close();
        final ok = await connect();
        if (ok) break;
      } catch (e) {
        LogBuffer.I.add('Reconnect error: $e');
      }
      await Future.delayed(Duration(milliseconds: _reconnectBackoffMs));
      _reconnectBackoffMs = (_reconnectBackoffMs * 13 ~/ 10).clamp(1500, 10000);
    }
    _reconnectLoopRunning = false;
  }();
}


  /// Siparişi başlatır ve event'leri dinlemeye başlar.
  ///
  /// Not: Bu fonksiyon "iş" yapmaz; sadece MCU'ya sipariş bildirir.
  Future<int> startOrder(BuzlimeOrder order) async {
    if (!_connected || _client == null) {
      throw ProtoError('DISCONNECTED', 'MCU not connected');
    }

    // Event dinleyicisi (bir kere kur)
    _eventSub ??= _client!.events.listen(_handleEvent);

    final resp = await _client!.sendCmd(
      'START_ORDER',
      payload: {
        'product': {
          'drink': order.drinkCode,
          'size_ml': order.sizeMl,
        },
        // Seri üretim: fiyat tablosu MCU'da otorite olmalı → app price göndermez.
        // (Geriye dönük: order.priceKurus alanı şimdilik tutuluyor ama kullanılmıyor.)
      },
      timeout: const Duration(seconds: 5),
    );

    // Beklenen cevap (pdf): data:{order_id, accepted:true, state:'WAIT_PAYMENT'}
final oid = asInt(resp.data?['order_id']) ?? asInt(resp.data?['orderId']);
    if (oid == null) {
      throw ProtoError('BAD_RESPONSE', 'order_id missing');
    }

    final accepted = resp.data?['accepted'];
    if (accepted == false) {
      throw ProtoError('REJECTED', 'START_ORDER not accepted');
    }
    _activeOrderId = oid;
    telemetry.orderId = oid;
    telemetry.state = asString(resp.data?['state']) ?? 'WAIT_PAYMENT';
    telemetry.priceKurus = asInt(resp.data?['price_kurus']);
    telemetryStream.add(telemetry);

    // İlk adım: ödeme bekleniyor
    stepStream.add(PrepStep.waitPayment);

    return oid;
  }

  Future<ProtoResponse> getStatus() async {
    if (!_connected || _client == null) {
      throw ProtoError('DISCONNECTED', 'MCU not connected');
    }
    return _client!.sendCmd('GET_STATUS', timeout: const Duration(seconds: 2));
  }

  void _handleEvent(ProtoEvent ev) {
    // Başka sipariş ise görmezden gel
    if (_activeOrderId != null && ev.orderId != _activeOrderId) return;

    telemetry.orderId = ev.orderId;
    telemetry.state = asString(ev.raw['state']) ?? telemetry.state;
    telemetry.progress = asDouble(ev.raw['progress']) ?? telemetry.progress;

    final pay = asMap(ev.raw['payment']);
    if (pay != null) {
      telemetry.priceKurus = asInt(pay['price_kurus']) ?? telemetry.priceKurus;
      telemetry.paidKurus = asInt(pay['paid_kurus']) ?? telemetry.paidKurus;
      telemetry.remainingKurus = asInt(pay['remaining_kurus']) ?? telemetry.remainingKurus;
    }

    telemetryStream.add(telemetry);

    if (ev.event == 'ORDER_STATUS') {
      final st = (telemetry.state ?? '').toUpperCase();
      // Bazı firmware sürümlerinde hata, ayrı ORDER_ERROR yerine ORDER_STATUS içinde state=ERROR/FAILED gibi gelir.
      if (st.contains('ERROR') || st.contains('FAIL') || st.contains('CANCEL')) {
        telemetry.lastErrorCode ??= 'UNKNOWN';
        telemetry.lastRecovery ??= 'ASK_USER';
        final cat = kErrorCatalogTr[telemetry.lastErrorCode] ?? kErrorCatalogTr['UNKNOWN']!;
        telemetry.lastError = cat['title'] ?? telemetry.lastErrorCode;
        telemetryStream.add(telemetry);
        stepStream.add(PrepStep.error);
        return;
      }
      if (st.contains('WAIT_PAYMENT')) {
        stepStream.add(PrepStep.waitPayment);
      } else if (st.contains('PAYMENT_OK')) {
        stepStream.add(PrepStep.paymentOk);
      } else {
        stepStream.add(PrepStep.preparing);
      }
      return;
    }

    if (ev.event == 'ORDER_DONE') {
      stepStream.add(PrepStep.done);
      return;
    }

    if (ev.event == 'ORDER_ERROR') {
      final errMap = asMap(ev.raw['error']);
      final code = asString(ev.raw['code']) ?? asString(errMap?['code']) ?? 'UNKNOWN';
      final msg = asString(ev.raw['msg']) ?? asString(errMap?['msg']) ?? '';
      final recovery = asString(ev.raw['recovery']) ?? asString(errMap?['recovery']);

      telemetry.lastErrorCode = code;
      telemetry.lastRecovery = recovery;

      final cat = kErrorCatalogTr[code] ?? kErrorCatalogTr['UNKNOWN']!;
      final title = cat['title'] ?? code;
      final hint = cat['hint'] ?? '';
      telemetry.lastError =
          msg.isNotEmpty ? '$title — $msg' : (hint.isNotEmpty ? '$title — $hint' : title);

      telemetryStream.add(telemetry);

      final rec = (recovery ?? '').toUpperCase();
      if (rec == 'AUTO_RETRY') {
        stepStream.add(PrepStep.preparing);
      } else {
        stepStream.add(PrepStep.error);
      }
      return;
    }
  }
}

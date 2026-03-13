// SPDX-License-Identifier: MIT
// protocol_client.dart
//
// DEĞİŞİKLİKLER:
//   - sendCmd()'den eski `params` parametresi tamamen kaldırıldı.
//     Tüm çağrı noktaları zaten `payload:` kullanıyor; geriye dönük
//     uyumluluk katmanına artık gerek yok.
//   - dispose() sync wrapper'ı kaldırıldı; close() doğrudan çağrılmalı.
//   - Pending completer'lar close() sırasında hata ile tamamlanır
//     → timeout beklenmeden temiz kapatma sağlanır.

import 'dart:async';
import 'dart:convert';

import 'protocol_v2.dart';
import '../core/log_buffer.dart';
import 'usb_cdc.dart';

/// USB-CDC üstünde istek/yanıt + event ayrıştırıcı.
///
/// Protokol (PDF v2):
///   TX: { "id":1, "type":"cmd", "cmd":"WATCHDOG", "v":2, "payload":{...} }\n
///   RX: { "id":1, "type":"response", "cmd":"WATCHDOG", "status":"ok", "data":{...}, "v":2 }
///   EV: { "type":"event", "event":"ORDER_STATUS", "order_id":77, ... }
class ProtocolClient {
  final UsbCdcTransport _transport;
  late final StreamSubscription _sub;

  int _nextId = 1;
  final Map<int, Completer<ProtoResponse>> _pending = {};
  final _eventsCtrl = StreamController<ProtoEvent>.broadcast();

  Stream<ProtoEvent> get events => _eventsCtrl.stream;

  ProtocolClient(this._transport) {
    _sub = _transport.messages.listen(
      _onMessage,
      onError: (_) {},
      onDone: () {},
    );
  }

  /// Tüm bekleyen istekleri iptal ederek kapatır.
  Future<void> close() async {
    // Bekleyen tüm completer'ları hata ile tamamla → timeout beklemeden temizlenir
    final error = ProtoError('CLIENT_CLOSED', 'ProtocolClient kapatıldı');
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _pending.clear();

    try { await _sub.cancel(); }    catch (_) {}
    try { await _eventsCtrl.close(); } catch (_) {}
  }

  /// MCU'ya komut gönderir; yanıt bekler.
  ///
  /// Parametreler:
  ///   [cmd]     – Komut adı ('WATCHDOG', 'GET_STATUS', 'START_ORDER', 'RESET')
  ///   [payload] – İsteğe bağlı JSON nesne (yoksa alanda yer almaz)
  ///   [timeout] – Yanıt bekleme süresi (varsayılan 5 sn)
  ///   [v]       – Protokol versiyonu (varsayılan kProtoV=2)
  Future<ProtoResponse> sendCmd(
      String cmd, {
        Map<String, dynamic>? payload,
        Duration timeout = const Duration(seconds: 5),
        int v = kProtoV,
      }) async {
    final id = _nextId++;
    final completer = Completer<ProtoResponse>();
    _pending[id] = completer;

    final msg = <String, dynamic>{
      'id':   id,
      'type': 'cmd',
      'cmd':  cmd,
      'v':    v,
      if (payload != null) 'payload': payload,
    };

    LogBuffer.I.add('TX ${jsonEncode(msg)}');
    await _transport.send(msg);

    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw ProtoError('TIMEOUT', 'Yanıt alınamadı: $cmd (id=$id)');
    });
  }

  // ── Gelen mesaj işleyici ─────────────────────────────────────────────────────
  void _onMessage(Map<String, dynamic> msg) {
    LogBuffer.I.add('RX ${jsonEncode(msg)}');
    final type = (msg['type'] ?? '').toString();

    // Response: { type:'response', id, cmd, status, data?, error? }
    if (type == 'response') {
      final resp = ProtoResponse.fromJson(msg);
      final c = _pending.remove(resp.id);
      if (c != null && !c.isCompleted) {
        if (resp.status == 'ok') {
          c.complete(resp);
        } else {
          c.completeError(resp.toError() ?? ProtoError('UNKNOWN', 'Bilinmeyen hata'));
        }
      }
      return;
    }

    // Event: { type:'event', event:'ORDER_STATUS', order_id, ... }
    if (type == 'event') {
      _dispatchEvent(msg);
      return;
    }

    // Bazı MCU sürümleri type alanını atlayabilir; event + order_id varsa event say.
    if (type.isEmpty &&
        msg.containsKey('event') &&
        msg.containsKey('order_id')) {
      _dispatchEvent({...msg, 'type': 'event'});
    }
  }

  void _dispatchEvent(Map<String, dynamic> raw) {
    try {
      final ev = ProtoEvent.fromJson(raw);
      if (!_eventsCtrl.isClosed) _eventsCtrl.add(ev);
    } catch (_) {
      // Hatalı event → yoksay, loglara düş
      LogBuffer.I.add('EV-PARSE-ERR ${jsonEncode(raw)}');
    }
  }
}
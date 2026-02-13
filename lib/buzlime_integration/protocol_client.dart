import 'dart:async';
import 'dart:convert';

import 'protocol_v2.dart';
import '../core/log_buffer.dart';
import 'usb_cdc.dart';

/// USB-CDC üstünde request/response + event ayrıştıran hafif istemci.
///
/// PDF v2 ile uyum:
/// - Komut: { "id":1, "type":"cmd", "cmd":"WATCHDOG", "v":2, "payload":{...} } + \n
/// - Cevap: { "id":1, "type":"response", "cmd":"WATCHDOG", "status":"ok|busy|error", "data":{...}, "error":{...}, "v":2 }
/// - Event: { "type":"event", "event":"ORDER_STATUS|ORDER_DONE|ORDER_ERROR", "order_id":77, ... }
class ProtocolClient {
  final UsbCdcTransport _transport;
  late final StreamSubscription _sub;

  int _nextId = 1;
  final Map<int, Completer<ProtoResponse>> _pending = {};
  final _eventsCtrl = StreamController<ProtoEvent>.broadcast();

  Stream<ProtoEvent> get events => _eventsCtrl.stream;

  ProtocolClient(this._transport) {
    _sub = _transport.messages.listen(_onMessage, onError: (_) {}, onDone: () {});
  }

  /// Graceful shutdown.
  ///
  /// Note: transport kapanışı üst katmanda (DeviceController) yönetiliyor.
  Future<void> close() async {
    try {
      await _sub.cancel();
    } catch (_) {}
    try {
      await _eventsCtrl.close();
    } catch (_) {}
    _pending.clear();
  }

  /// Back-compat: eski yerlerde sync çağrılabiliyor.
  void dispose() {
    // ignore: discarded_futures
    close();
  }

  /// Komut gönderir ve response bekler.
  ///
  /// Not: Eski koddan gelen `params` varsa otomatik `payload` içine taşınır.
  Future<ProtoResponse> sendCmd(
    String cmd, {
    Map<String, dynamic>? payload,
    Map<String, dynamic>? params, // DEPRECATED: geriye dönük uyumluluk
    Duration timeout = const Duration(seconds: 5),
    int v = kProtoV,
  }) async {
    final id = _nextId++;
    final completer = Completer<ProtoResponse>();
    _pending[id] = completer;

    // Back-compat: params -> payload
    final effectivePayload = payload ?? (params == null ? null : Map<String, dynamic>.from(params));

    final msg = {
      'id': id,
      'type': 'cmd',
      'cmd': cmd,
      'v': v,
      if (effectivePayload != null) 'payload': effectivePayload,
    };

    LogBuffer.I.add('TX ' + jsonEncode(msg));
    await _transport.send(msg);

    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw ProtoError('TIMEOUT', 'No response for $cmd (id=$id)');
    });
  }

  void _onMessage(Map<String, dynamic> msg) {
    LogBuffer.I.add('RX ' + jsonEncode(msg));
    final type = (msg['type'] ?? '').toString();

    // Response format: {v, type:'response', id, cmd, status, data?, error?}
    if (type == 'response') {
      final resp = ProtoResponse.fromJson(msg);
      final c = _pending.remove(resp.id);
      if (c != null && !c.isCompleted) {
        if (resp.status == 'ok') {
          c.complete(resp);
        } else {
          c.completeError(resp.toError() ?? ProtoError('UNKNOWN', 'Unknown error'));
        }
      }
      return;
    }

    // Event format: {v, type:'event', event:'ORDER_STATUS', order_id, ...}
    if (type == 'event') {
      try {
        final ev = ProtoEvent.fromJson(msg);
        _eventsCtrl.add(ev);
      } catch (_) {
        // malformed -> ignore
      }
      return;
    }

    // Bazı MCU sürümlerinde type alanı unutulabilir:
    // - event alanı varsa event say.
    if (type.isEmpty && msg.containsKey('event') && msg.containsKey('order_id')) {
      try {
        final ev = ProtoEvent.fromJson({...msg, 'type': 'event'});
        _eventsCtrl.add(ev);
      } catch (_) {}
    }
  }
}

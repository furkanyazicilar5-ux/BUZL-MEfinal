// SPDX-License-Identifier: MIT
// command_queue.dart
//
// DEĞİŞİKLİKLİK:
//   - V1 Cmd sınıfı models.dart'tan kaldırıldığı için send(Cmd) imzası
//     Map<String, dynamic> tabanlıya dönüştürüldü.
//   - Cmd.toJson() referansı kaldırıldı; çağıran taraf doğrudan ham Map verir.
//   - Geri kalan mantık (id eşleştirme, pending map, timeout) aynen korundu.
//
// NOT: Bu sınıf V1 test/diagnostic akışları için bırakılmıştır.
// Tüm üretim sipariş akışları DeviceController + ProtocolClient üzerinden
// yürütülür (protocol v2).

import 'dart:async';
import 'dart:math';
import 'usb_cdc.dart';

class CommandQueue {
  final UsbCdcTransport transport;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  late final StreamSubscription _sub;

  CommandQueue(this.transport) {
    _sub = transport.messages.listen(_onMessage);
  }

  void dispose() {
    _sub.cancel();
    // Bekleyen tüm completer'ları hata ile kapat
    final err = Exception('CommandQueue disposed');
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(err);
    }
    _pending.clear();
  }

  void _onMessage(Map<String, dynamic> msg) {
    final id = (msg['ack']?['id'] ??
        msg['id'] ??
        msg['resp']?['id'] ??
        msg['err']?['id'])
        ?.toString();
    if (id != null && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(msg);
    }
  }

  String _genId() =>
      DateTime.now().microsecondsSinceEpoch.toString() +
          Random().nextInt(999).toString();

  /// Ham JSON map gönderir.
  ///
  /// Mesajda 'id' alanı yoksa otomatik atanır.
  /// [timeout] varsayılan 5 sn (USB + MCU gecikme toleransı için).
  Future<Map<String, dynamic>> send(
      Map<String, dynamic> cmd, {
        Duration timeout = const Duration(seconds: 5),
      }) async {
    // id yoksa üret ve ekle
    final String id = cmd['id']?.toString() ?? _genId();
    final msgToSend = {...cmd, 'id': id};

    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    await transport.send(msgToSend);
    return c.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('CommandQueue timeout (id=$id)');
    });
  }
}
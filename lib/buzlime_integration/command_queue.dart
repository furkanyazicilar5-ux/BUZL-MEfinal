
import 'dart:async';
import 'dart:math';
import 'models.dart';
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
  }

  void _onMessage(Map<String, dynamic> msg) {
    final id = (msg['ack']?['id'] ?? msg['id'] ?? msg['resp']?['id'] ?? msg['err']?['id'])?.toString();
    if (id != null && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(msg);
    }
  }

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString() + Random().nextInt(999).toString();

  /// Default timeout increased to 5 seconds to tolerate USB and MCU latencies.
  Future<Map<String, dynamic>> send(Cmd cmd, {Duration timeout = const Duration(seconds: 5)}) async {
    final c = Completer<Map<String, dynamic>>();
    _pending[cmd.id] = c;
    await transport.send(cmd.toJson());
    return c.future.timeout(timeout);
  }
}

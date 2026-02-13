// usb_cdc.dart — COMPAT PATCH for usb_serial 0.5.2 .. 0.5.7
// Path: lib/buzlime_integration/usb_cdc.dart
//
// Differences handled:
// - Do NOT import usb_port.dart (older versions don't have it public)
// - Do NOT call UsbSerial.requestPermission() (older versions may not expose it)
// - Port.write(...) may return void/bool/int depending on version → don't check the return
//
// Usage stays the same for the rest of the app.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/log_buffer.dart';

import 'package:usb_serial/usb_serial.dart';
// NOTE: Don't import usb_port.dart for compatibility.

import 'device_protocol.dart';

class UsbCdcTransport {
  final int vendorIdHint;
  final int productIdHint;
  final int baudRate;
  final bool autoPickFirstIfNoMatch;

  UsbPort? _port;
  StreamSubscription<Uint8List>? _sub;
  final _rxCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final StringBuffer _lineBuf = StringBuffer();

  Stream<Map<String, dynamic>> get messages => _rxCtrl.stream;

  UsbCdcTransport({
    this.vendorIdHint = 0x2341,
    this.productIdHint = 0x8036,
    this.baudRate = 115200,
    this.autoPickFirstIfNoMatch = true,
  });

  Future<void> open() async {
    LogBuffer.I.add('USB open()');
    final devices = await UsbSerial.listDevices();
    UsbDevice? chosen;

    for (final d in devices) {
      if ((d.vid == vendorIdHint) && (d.pid == productIdHint)) {
        chosen = d;
        break;
      }
    }
    if (chosen == null && autoPickFirstIfNoMatch && devices.isNotEmpty) {
      chosen = devices.first;
    }
    if (chosen == null) {
      throw Exception("USB-CDC: Uygun cihaz bulunamadı. Cihazı takıp izin verin.");
    }

    // Some versions require permission via intent-filter and prompt automatically.
    // We avoid calling UsbSerial.requestPermission() for widest compatibility.

    _port = await chosen.create();
    if (_port == null) {
      throw Exception("USB-CDC: Port oluşturulamadı.");
    }

    final opened = await _port!.open();
    if (opened != true) {
      throw Exception("USB-CDC: Port açılamadı.");
    }

    // Older versions always return Future<void>, so we just await without checks.
    await _port!.setDTR(true);
    await _port!.setRTS(true);

    // setPortParameters exists across versions; signature is (baud, dataBits, stopBits, parity)
    // We reference constants on UsbPort via the same type to avoid extra imports.
    await _port!.setPortParameters(
      baudRate,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    _sub = _port!.inputStream?.listen(_onBytes,
        onError: (e, st) => _rxCtrl.add({'ok': false, 'err': {'reason': 'inputStream error: $e'}}),
        cancelOnError: false);
  }

  void _onBytes(Uint8List data) {
    final chunk = utf8.decode(data, allowMalformed: true);
    _lineBuf.write(chunk);
    final txt = _lineBuf.toString();
    final parts = txt.split('\n');
    for (int i = 0; i < parts.length - 1; i++) {
      final line = parts[i].trim();
      if (line.isEmpty) continue;
      final j = tryDecode(line);
      if (j != null) {
        _rxCtrl.add(j);
      } else {
        final short = line.length > 200 ? line.substring(0, 200) + '…' : line;
        LogBuffer.I.add('RX-RAW ' + short);
      }
    }
    _lineBuf.clear();
    _lineBuf.write(parts.last);
  }

  Future<void> send(Map<String, dynamic> json) async {
    final line = encode(json); // adds trailing \n
    final bytes = Uint8List.fromList(utf8.encode(line));
    await _port?.write(bytes); // return type may be void/bool/int → don't check
  }

  Future<void> close() async {
    LogBuffer.I.add('USB close()');
    await _sub?.cancel();
    _sub = null;
    try { await _port?.close(); } catch (_) {}
    _port = null;
    await _rxCtrl.close();
  }
}

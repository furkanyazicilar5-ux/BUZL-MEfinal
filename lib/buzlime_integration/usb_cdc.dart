// SPDX-License-Identifier: MIT
// usb_cdc.dart — COMPAT PATCH for usb_serial 0.5.2 .. 0.5.7
//
// DEĞİŞİKLİKLER:
//   1) _lineBuf tampon sınırı eklendi (kLineBufMax = 2048 karakter).
//      Satır sonu (\n) gelmeden tampon doluyorsa içerik sıfırlanır;
//      hatalı/eksik veri nedeniyle bellek şişmesi engellenir.
//   2) open() → _rxCtrl yeniden kullanılabilir hale getirildi.
//      Eski close() → StreamController.close() çağrısı sonrası
//      tekrar open() yapılırsa "Stream closed" exception olurdu.
//      Düzeltme: _rxCtrl hiç kapatılmıyor; port hatalarında sadece
//      port kapatılır, stream controller açık kalır.
//   3) close() sırasında _rxCtrl.close() KALDIRILDI — DeviceController
//      yeniden bağlandığında aynı UsbCdcTransport örneği üzerinden
//      tekrar open() çağrılabilir; stream hâlâ dinlenebilir durumda olur.
//      (DeviceController singleton olduğu için transport da singleton'dır.)
//
// NOT: Bu değişiklikler DeviceController._ensureReconnectLoop() içinde
// listDevices() yeniden çağrılmasını mümkün kılar.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/log_buffer.dart';
import 'package:usb_serial/usb_serial.dart';
import 'device_protocol.dart';

class UsbCdcTransport {
  // ── Yapılandırma ─────────────────────────────────────────────────────────────
  final int  vendorIdHint;
  final int  productIdHint;
  final int  baudRate;
  final bool autoPickFirstIfNoMatch;

  // ── Tampon sınırı ─────────────────────────────────────────────────────────────
  /// Satır sonu (\n) gelmeden _lineBuf bu boyutu aşarsa tampon sıfırlanır.
  /// Hatalı / kesilmiş veri akışında bellek şişmesini önler.
  static const int kLineBufMax = 2048;

  // ── İç durum ─────────────────────────────────────────────────────────────────
  UsbPort? _port;
  StreamSubscription<Uint8List>? _inputSub;

  // _rxCtrl KAPATILMAZ — DeviceController yeniden bağlandığında
  // aynı stream üzerinden mesaj almaya devam etmek için açık tutulur.
  final _rxCtrl   = StreamController<Map<String, dynamic>>.broadcast();
  final _lineBuf  = StringBuffer();

  Stream<Map<String, dynamic>> get messages => _rxCtrl.stream;
  bool get isOpen => _port != null;

  UsbCdcTransport({
    this.vendorIdHint        = 0x2341,
    this.productIdHint       = 0x8036,
    this.baudRate            = 115200,
    this.autoPickFirstIfNoMatch = true,
  });

  // ── Bağlan ───────────────────────────────────────────────────────────────────
  /// USB cihazını bulur, baud ayarını yapar ve veri akışını başlatır.
  /// Zaten açıksa önce kapatır.
  Future<void> open() async {
    // Önceki bağlantı varsa temizle (stream controller açık kalır)
    await _closePort();

    LogBuffer.I.add('USB open(): cihaz taranıyor...');
    final devices = await UsbSerial.listDevices();
    LogBuffer.I.add('USB listDevices(): ${devices.length} cihaz bulundu');

    UsbDevice? chosen;
    for (final d in devices) {
      if (d.vid == vendorIdHint && d.pid == productIdHint) {
        chosen = d;
        break;
      }
    }
    if (chosen == null && autoPickFirstIfNoMatch && devices.isNotEmpty) {
      chosen = devices.first;
      LogBuffer.I.add('USB: VID/PID eşleşmedi, ilk cihaz seçildi: '
          'VID=${chosen.vid} PID=${chosen.pid}');
    }
    if (chosen == null) {
      throw Exception('USB-CDC: Uygun cihaz bulunamadı. '
          'Kabloyu takın ve izin verin.');
    }

    _port = await chosen.create();
    if (_port == null) throw Exception('USB-CDC: Port oluşturulamadı.');

    final opened = await _port!.open();
    if (opened != true) throw Exception('USB-CDC: Port açılamadı.');

    await _port!.setDTR(true);
    await _port!.setRTS(true);
    await _port!.setPortParameters(
      baudRate,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    // Tampon sıfırla (önceki yarım frame kalıntısı olabilir)
    _lineBuf.clear();

    _inputSub = _port!.inputStream?.listen(
      _onBytes,
      onError: (e) {
        LogBuffer.I.add('USB inputStream hata: $e');
        // Hata event'i stream'e göndermiyoruz — DeviceController watchdog yakalar
      },
      cancelOnError: false,
    );

    LogBuffer.I.add('USB open(): başarılı.');
  }

  // ── Gelen byte işleyici ───────────────────────────────────────────────────────
  void _onBytes(Uint8List data) {
    final chunk = utf8.decode(data, allowMalformed: true);
    _lineBuf.write(chunk);

    // ── Tampon taşma koruması ────────────────────────────────────────────────
    // Satır sonu gelmiyor ve tampon büyüyorsa: hatalı/garbled veri.
    // Tampon içeriğini log'a at ve sıfırla.
    if (_lineBuf.length > kLineBufMax) {
      final preview = _lineBuf.toString().substring(0, 120);
      LogBuffer.I.add(
        'USB _lineBuf taşma (${_lineBuf.length} > $kLineBufMax): sıfırlanıyor. '
            'Önizleme: $preview…',
      );
      _lineBuf.clear();
      return;
    }

    // ── Satır bazlı JSON ayrıştırma ──────────────────────────────────────────
    final txt   = _lineBuf.toString();
    final parts = txt.split('\n');

    // Son parça: henüz tamamlanmamış satır — tamponda sakla
    for (int i = 0; i < parts.length - 1; i++) {
      final line = parts[i].trim();
      if (line.isEmpty) continue;

      final j = tryDecode(line);
      if (j != null) {
        if (!_rxCtrl.isClosed) _rxCtrl.add(j);
      } else {
        final preview = line.length > 200 ? '${line.substring(0, 200)}…' : line;
        LogBuffer.I.add('USB RX-RAW (JSON değil): $preview');
      }
    }

    _lineBuf.clear();
    _lineBuf.write(parts.last); // tamamlanmamış satırı geri koy
  }

  // ── Gönder ───────────────────────────────────────────────────────────────────
  Future<void> send(Map<String, dynamic> json) async {
    if (_port == null) {
      LogBuffer.I.add('USB send(): port kapalı, mesaj atlandı.');
      return;
    }
    final line  = encode(json); // encode() sona \n ekler
    final bytes = Uint8List.fromList(utf8.encode(line));
    await _port?.write(bytes); // dönüş tipi sürüme göre void/bool/int → kontrol yok
  }

  // ── Kapat ────────────────────────────────────────────────────────────────────
  /// Portu ve input stream aboneliğini kapatır.
  /// _rxCtrl KAPATILMAZ — bir sonraki open() sonrası stream hâlâ dinlenebilir.
  Future<void> close() async {
    LogBuffer.I.add('USB close()');
    await _closePort();
  }

  // ── Yardımcı: sadece port kaynaklarını serbest bırak ────────────────────────
  Future<void> _closePort() async {
    await _inputSub?.cancel();
    _inputSub = null;
    try { await _port?.close(); } catch (_) {}
    _port = null;
    _lineBuf.clear(); // Artık geçersiz olan kısmi veriyi temizle
  }
}
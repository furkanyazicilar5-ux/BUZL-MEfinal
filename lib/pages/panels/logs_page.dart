// SPDX-License-Identifier: MIT
// logs_page.dart
//
// DEĞİŞİKLİKLİK:
//   - DeviceController artık `telemetry` alanını doğrudan dışa açmıyor
//     (_tel private olarak yeniden adlandırıldı). Bunun yerine son telemetri
//     snapshot'ı bu sayfada yerel olarak tutulur.
//   - initState() içinde telemetryStream dinleyicisi kurulur; her güncelleme
//     _lastTel'i günceller ve _refresh() tetiklenir.
//   - Sayfa dispose edildiğinde abonelik iptal edilir.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/log_buffer.dart';
import '../../core/app_info.dart';
import '../../buzlime_integration/integration_entry.dart';
import '../../buzlime_integration/models.dart';
import 'dart:async';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  List<String> _lines = const [];
  Telemetry _lastTel = Telemetry();
  StreamSubscription? _telSub;

  @override
  void initState() {
    super.initState();

    // Telemetri güncellemelerini dinle — her yeni snapshot sayfayı tazeler
    final dev = getDeviceController();
    _telSub = dev.telemetryStream.stream.listen((t) {
      _lastTel = t; // copy() ile gönderildiği için güvenle saklayabiliriz
      if (mounted) _refresh();
    });

    _refresh();
  }

  @override
  void dispose() {
    _telSub?.cancel();
    super.dispose();
  }

  void _refresh() {
    final t = _lastTel;
    final header = [
      '─── UYGULAMA ───────────────────────────────',
      'app_version=$kAppVersion  proto=$kProtoVersion',
      '─── CİHAZ ──────────────────────────────────',
      'device_id=${t.deviceId ?? '-'}  fw=${t.fwVersion ?? '-'}',
      'state=${t.state ?? '-'}  order_id=${t.orderId ?? '-'}',
      'progress=${t.progress?.toStringAsFixed(2) ?? '-'}',
      'price=${t.priceKurus ?? '-'} kuruş  '
          'paid=${t.paidKurus ?? '-'}  '
          'remaining=${t.remainingKurus ?? '-'}',
      'last_error=${t.lastError ?? '-'}  '
          'code=${t.lastErrorCode ?? '-'}  '
          'recovery=${t.lastRecovery ?? '-'}',
      '─── LOG ────────────────────────────────────',
    ];
    setState(() {
      _lines = [...header, ...LogBuffer.I.snapshot()];
    });
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log panoya kopyalandı')),
    );
  }

  void _clearLog() {
    LogBuffer.I.clear();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihaz Logları'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Kopyala',
            onPressed: _copyAll,
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: 'Temizle',
            onPressed: _clearLog,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _lines.isEmpty
          ? const Center(child: Text('Log yok.'))
          : ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _lines.length,
        itemBuilder: (_, i) {
          final line = _lines[i];
          final isSeparator = line.startsWith('───');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              line,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: isSeparator ? 11 : 12,
                fontWeight: isSeparator
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: isSeparator
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}
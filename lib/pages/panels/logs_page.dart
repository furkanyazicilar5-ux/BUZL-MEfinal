import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/log_buffer.dart';
import '../../core/app_info.dart';
import '../../buzlime_integration/integration_entry.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  List<String> _lines = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final dev = getDeviceController();
    final t = dev.telemetry;
    final header = [
      '--- APP ---',
      'app_version=$kAppVersion proto=$kProtoVersion',
      '--- DEVICE ---',
      'device_id=${t.deviceId ?? '-'} fw_version=${t.fwVersion ?? '-'}',
      'state=${t.state ?? '-'} order_id=${t.orderId ?? '-'}',
      'last_error=${t.lastError ?? '-'} code=${t.lastErrorCode ?? '-'} recovery=${t.lastRecovery ?? '-'}',
      '--- LOG ---',
    ];
    setState(() {
      _lines = [...header, ...LogBuffer.I.snapshot()];
    });
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log kopyalandı')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _copyAll, icon: const Icon(Icons.copy)),
          IconButton(
            onPressed: () {
              LogBuffer.I.clear();
              _refresh();
            },
            icon: const Icon(Icons.delete),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _lines.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            _lines[i],
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
    );
  }
}

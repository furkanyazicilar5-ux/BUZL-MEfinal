import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/app_info.dart';

// Local panel pages
import 'logs_page.dart';

import '../../widgets/service_widgets/liquid_control_card.dart';
import '../../widgets/service_widgets/machine_service.dart';
import '../../widgets/service_widgets/stock_control_card.dart';

class ServicePanelPage extends StatefulWidget {
  const ServicePanelPage({super.key});

  @override
  State<ServicePanelPage> createState() => _ServicePanelPageState();
}

class _ServicePanelPageState extends State<ServicePanelPage> {
  final _service = MachineService(machineId: kMachineId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Servis Paneli'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            final confirm = await showExitConfirmation(context);
            if (confirm == true) {
              await _service.finishMaintenance(context, exit: true);
            }
          },
        ),
      ),
      body: StreamBuilder(
        stream: _service.machineStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Makine verisi bulunamadı.'));
          }

          final data = snapshot.data!;
          final inventory = data['inventory'] ?? {};
          final levels = data['levels'] ?? {};
          final status = data['status'] ?? {};

          final isActive = status['isActive'] ?? false;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                StockControlCard(
                  label: 'Büyük Bardak Sayısı',
                  value: inventory['largeCups'] ?? 0,
                  field: 'largeCups',
                  maxVal: 150,
                  onUpdate: _service.updateStock,
                  onFull: _service.setStockFull,
                ),
                StockControlCard(
                  label: 'Küçük Bardak Sayısı',
                  value: inventory['smallCups'] ?? 0,
                  field: 'smallCups',
                  maxVal: 160,
                  onUpdate: _service.updateStock,
                  onFull: _service.setStockFull,
                ),
                LiquidControlCard(
                  value: levels['liquid'] ?? 0,
                  maxVal: 80000,
                  onChange: (newValue, duration) async {
                    final now = DateTime.now();

                    // Eğer süre 0 seçildiyse isActive false olmalı
                    if (duration == 0) {
                      await _service.machineRef.update({
                        'levels.liquid': newValue,
                        'levels.liquidBand':
                            _service.bandForLiquid(newValue, 80000),
                        'processing.isActive': false,
                        'processing.until': null,
                      });
                      return;
                    }

                    final until = Timestamp.fromDate(
                        now.add(Duration(minutes: duration)));
                    await _service.machineRef.update({
                      'levels.liquid': newValue,
                      'levels.liquidBand':
                          _service.bandForLiquid(newValue, 80000),
                      'processing.isActive': true,
                      'processing.until': until,
                    });
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _service.toggleMachineStatus(isActive),
                  icon: Icon(isActive ? Icons.pause : Icons.play_arrow),
                  label: Text(isActive ? 'Satışı Kapat' : 'Satışı Aç'),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    final confirm = await showExitConfirmation(context);
                    if (confirm == true) {
                      await _service.finishMaintenance(context);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.build_circle_outlined),
                  label: const Text('Bakım Tamamlandı'),
                ),

const SizedBox(height: 16),
Card(
  child: ListTile(
    leading: const Icon(Icons.receipt_long),
    title: const Text('Loglar / USB Protokol'),
    subtitle: const Text('Saha teşhisi için kopyala / temizle'),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LogsPage()),
      );
    },
  ),
),
              ],
            ),
          );
        },
      ),
    );
  }
}

Future<bool?> showExitConfirmation(BuildContext context) async {
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Emin misiniz?'),
      content: const Text('Bakımı tamamlayıp çıkmak istiyor musunuz?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Hayır'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Evet'),
        ),
      ],
    ),
  );
}

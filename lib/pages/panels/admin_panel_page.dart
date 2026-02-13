import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/app_info.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  final machineRef = FirebaseFirestore.instance.collection('machines').doc(kMachineId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Admin Paneli SERVİCE PANEL KULLANIN !',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold,fontSize: 32.0),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: machineRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Makine verisi bulunamadı.'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final inventory = data['inventory'] ?? {};
          final levels = data['levels'] ?? {};
          final dailyProfit = data['daily_profit'] ?? {};
          final refunds = data['refunds'] ?? {};
          final sales = data['sales'] ?? {};
          final status = data['status'] ?? {};

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Makine Bilgileri',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildEditableSection('Stok (inventory)', inventory,
                    'inventory', {'largeCups': 120, 'smallCups': 150}),
                _buildEditableSection(
                    'Seviye (levels)', levels, 'levels', {'liquid': 20000}),
                const SizedBox(height: 16),
                SizedBox(
                  child: GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    childAspectRatio: 3,
                    children: [
                      _buildReadOnlyCard('Günlük Kar', {
                        'Tarih': dailyProfit['current_day'] ?? '-',
                        'Bugünkü Kar': '${dailyProfit['profit_today'] ?? 0} ₺',
                      }),
                      _buildReadOnlyCard('Satış Bilgileri', {
                        'Büyük Satış':
                            '${sales['largeSold'] ?? 0} (${sales['largeTl'] ?? 0} ₺)',
                        'Küçük Satış':
                            '${sales['smallSold'] ?? 0} (${sales['smallTl'] ?? 0} ₺)',
                      }),
                      _buildReadOnlyCard('İade Bilgileri', {
                        'Toplam İade': '${refunds['total'] ?? 0}',
                        'Miktar (ml)': '${refunds['amountMl'] ?? 0}',
                        'Tutar (₺)': '${refunds['amountTl'] ?? 0}',
                      }),
                      _buildReadOnlyCard('Durum', {
                        'Satış Aktif mi':
                            (status['isActive'] ?? false) ? 'Evet' : 'Hayır'
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.build_circle_outlined),
                    label: const Text('Bakım Kaydı Ekle'),
                    onPressed: () async {
                      await machineRef.collection('maintenance_logs').add({
                        'timestamp': FieldValue.serverTimestamp(),
                        'performedBy': 'admin@system',
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Bakım kaydı başarıyla eklendi')),
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

  Widget _buildReadOnlyCard(String title, Map<String, dynamic> info) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...info.entries.map((e) => Text('${e.key}: ${e.value}',
                style: const TextStyle(fontSize: 16))),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableSection(String title, Map<String, dynamic> data,
      String path, Map<String, int> limits) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...data.entries.where((e) => e.value is num).map((e) {
              final key = e.key;
              final value = e.value ?? 0;
              final maxVal = limits[key] ?? 100;
              final pct = (value / maxVal).clamp(0.0, 1.0);
              Color barColor = pct < 0.2
                  ? Colors.red
                  : (pct < 0.5 ? Colors.orange : Colors.teal);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$key: $value', style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                        value: pct,
                        color: barColor,
                        backgroundColor: Colors.grey[300],
                        minHeight: 10),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        IconButton(
                            onPressed: () =>
                                _updateValue(path, key, value - 5, maxVal),
                            icon: const Icon(Icons.remove_circle_outline)),
                        IconButton(
                            onPressed: () =>
                                _updateValue(path, key, value + 5, maxVal),
                            icon: const Icon(Icons.add_circle_outline)),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () =>
                              _updateValue(path, key, maxVal, maxVal),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white),
                          child: Text('Tam ($maxVal)'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                            onPressed: () =>
                                _enterManualValue(path, key, maxVal),
                            child: const Text('Değer Gir')),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _updateValue(
      String path, String key, int newValue, int maxVal) async {
    final updated = newValue.clamp(0, maxVal);
    await machineRef.update({'$path.$key': updated});
  }

  Future<void> _enterManualValue(String path, String key, int maxVal) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Değer Gir'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Yeni değer girin'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal')),
          TextButton(
            onPressed: () async {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 0 || value > maxVal) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Değer 0 ile $maxVal arasında olmalı.')));
                return;
              }
              await machineRef.update({'$path.$key': value});
              Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}

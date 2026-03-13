import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/app_colors.dart';
import '../../core/app_info.dart';
import '../processing_page.dart';
import '../../home_page.dart';

/// AdminPanelPage — Revize Edildi
///
/// MANTIK:
/// - Kullanıcı sayfaya girerken _levelChanged = false olarak başlar.
/// - Herhangi bir içecek seviyesi "Tam" yapılırsa _levelChanged = true işaretlenir.
///   Firestore yazımı ANİNDE yapılır; sadece navigasyon ertelenir.
/// - Sayfa kapatılırken (geri butonu veya çıkış):
///     * _levelChanged == true  → ProcessingPage (90 dakika kronometre)
///     * _levelChanged == false → HomePage (normal çıkış)
class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  final machineRef =
  FirebaseFirestore.instance.collection('machines').doc(kMachineId);

  // ─── SABİT MAKSİMUM DEĞERLER ─────────────────────────────────────────────
  static const int kSmallCupsMax = 150;
  static const int kLargeCupsMax = 120;
  static const int kLemonMax = 19000;
  static const int kOrangeMax = 19000;

  /// İçecek seviyesi bu oturumda "Tam" yapıldı mı?
  bool _levelChanged = false;

  /// Çıkış mantığı: seviye değiştiyse → ProcessingPage (90 dk), değilse → HomePage
  Future<bool> _onWillPop() async {
    if (_levelChanged) {
      await _activateProcessing();
      if (!mounted) return false;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ProcessingPage()),
            (route) => false,
      );
      return false;
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
            (route) => false,
      );
      return false;
    }
  }

  /// Firestore'a 90 dakika processing kaydı yaz
  Future<void> _activateProcessing() async {
    final now = DateTime.now();
    final until = Timestamp.fromDate(now.add(const Duration(minutes: 90)));
    await machineRef.update({
      'processing.isActive': true,
      'processing.until': until,
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _onWillPop(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: AppColors.bzPrimaryDark,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: _onWillPop,
          ),
          title: const Text(
            'Admin Paneli',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
          actions: [
            if (_levelChanged)
              Container(
                margin: const EdgeInsets.only(right: 14),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.timer_outlined, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      '90 dk bekleme aktif',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
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

            final smallCups = (inventory['smallCups'] ?? 0) as int;
            final largeCups = (inventory['largeCups'] ?? 0) as int;
            final lemonLevel = (levels['lemon'] ?? levels['liquid'] ?? 0) as int;
            final orangeLevel = (levels['orange'] ?? 0) as int;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Seviye değişikliği uyarı banner'ı
                  if (_levelChanged) ...[
                    _buildWarningBanner(),
                    const SizedBox(height: 16),
                  ],

                  _sectionTitle('🥤 Bardak Stokları'),
                  const SizedBox(height: 8),
                  _buildStockCard(
                    label: 'Küçük Bardak',
                    icon: Icons.local_drink_outlined,
                    value: smallCups,
                    maxVal: kSmallCupsMax,
                    path: 'inventory',
                    key: 'smallCups',
                    unit: 'adet',
                    color: AppColors.bzPrimary,
                  ),
                  _buildStockCard(
                    label: 'Büyük Bardak',
                    icon: Icons.coffee_outlined,
                    value: largeCups,
                    maxVal: kLargeCupsMax,
                    path: 'inventory',
                    key: 'largeCups',
                    unit: 'adet',
                    color: AppColors.bzPrimary,
                  ),

                  const SizedBox(height: 24),

                  _sectionTitle('🍋 İçecek Seviyeleri'),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.amber.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '"Tam" butonuna basıldığında işlemler tamamlandıktan sonra çıkışta 90 dakika bekleme süreci başlar.',
                            style: TextStyle(
                                color: Colors.amber.shade800, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildLiquidCard(
                    label: 'Limon',
                    icon: '🍋',
                    value: lemonLevel,
                    maxVal: kLemonMax,
                    path: 'levels',
                    key: 'lemon',
                    color: const Color(0xFFF9C74F),
                  ),
                  _buildLiquidCard(
                    label: 'Portakal',
                    icon: '🍊',
                    value: orangeLevel,
                    maxVal: kOrangeMax,
                    path: 'levels',
                    key: 'orange',
                    color: Colors.orange,
                  ),

                  const SizedBox(height: 24),

                  _sectionTitle('📊 Genel Bilgiler'),
                  const SizedBox(height: 8),
                  _buildInfoGrid(dailyProfit, sales, refunds, status),

                  const SizedBox(height: 24),
                  _buildMaintenanceButton(),

                  const SizedBox(height: 32),
                  _buildExitButton(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade600, Colors.deepOrange.shade400],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.orange.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('İçecek doldurma işlemi kaydedildi',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                Text('Çıkışta 90 dakika bekleme ekranı başlayacak.',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A2B3C)),
    );
  }

  // ─── BARDAK STOK KARTI ────────────────────────────────────────────────────
  Widget _buildStockCard({
    required String label,
    required IconData icon,
    required int value,
    required int maxVal,
    required String path,
    required String key,
    required String unit,
    required Color color,
  }) {
    final pct = (value / maxVal).clamp(0.0, 1.0);
    final barColor = pct < 0.2
        ? Colors.red
        : (pct < 0.5 ? Colors.orange : color);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: barColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$value / $maxVal $unit',
                    style: TextStyle(
                        color: barColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                color: barColor,
                backgroundColor: Colors.grey[200],
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _iconBtn(Icons.remove, () => _updateIntValue(path, key, value - 5, maxVal)),
                _iconBtn(Icons.add, () => _updateIntValue(path, key, value + 5, maxVal)),
                const SizedBox(width: 8),
                _pillButton(
                  label: 'Tam',
                  color: Colors.teal,
                  onPressed: () => _updateIntValue(path, key, maxVal, maxVal),
                ),
                const SizedBox(width: 8),
                _pillButton(
                  label: 'Değer Gir',
                  color: Colors.blueGrey,
                  onPressed: () => _enterManualValue(path, key, maxVal),
                  outlined: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── İÇECEK SEVİYE KARTI ─────────────────────────────────────────────────
  Widget _buildLiquidCard({
    required String label,
    required String icon,
    required int value,
    required int maxVal,
    required String path,
    required String key,
    required Color color,
  }) {
    final pct = (value / maxVal).clamp(0.0, 1.0);
    final barColor =
    pct < 0.2 ? Colors.red : (pct < 0.5 ? Colors.orange : color);
    final pctStr = '${(pct * 100).toStringAsFixed(0)}%';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: barColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$value mL ($pctStr)',
                    style: TextStyle(
                        color: barColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                color: barColor,
                backgroundColor: Colors.grey[200],
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _iconBtn(Icons.remove,
                        () => _updateIntValue(path, key, value - 500, maxVal),
                    tooltip: '-500 mL'),
                _iconBtn(Icons.add,
                        () => _updateIntValue(path, key, value + 500, maxVal),
                    tooltip: '+500 mL'),
                const SizedBox(width: 8),
                // "Tam" → sadece Firestore'a yaz + _levelChanged = true
                // Navigasyon çıkışta yapılacak
                _pillButton(
                  label: 'Tam (${maxVal ~/ 1000}L)',
                  color: Colors.teal,
                  onPressed: () => _setLiquidFull(path, key, maxVal),
                ),
                const SizedBox(width: 8),
                _pillButton(
                  label: 'Değer Gir',
                  color: Colors.blueGrey,
                  onPressed: () => _enterManualValue(path, key, maxVal),
                  outlined: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _pillButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool outlined = false,
  }) {
    if (outlined) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 13)),
      );
    }
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  // ─── BİLGİ GRİDİ ──────────────────────────────────────────────────────────
  Widget _buildInfoGrid(Map dp, Map sales, Map refunds, Map status) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: [
        _infoCard('📈 Günlük Kar', [
          '${dp['current_day'] ?? '-'}',
          '${dp['profit_today'] ?? 0} ₺',
        ], Colors.green),
        _infoCard('🧾 Satışlar', [
          'Büyük: ${sales['largeSold'] ?? 0} (${sales['largeTl'] ?? 0}₺)',
          'Küçük: ${sales['smallSold'] ?? 0} (${sales['smallTl'] ?? 0}₺)',
        ], Colors.blue),
        _infoCard('↩️ İadeler', [
          'Adet: ${refunds['total'] ?? 0}',
          '${refunds['amountTl'] ?? 0}₺ / ${refunds['amountMl'] ?? 0}mL',
        ], Colors.orange),
        _infoCard('⚡ Durum', [
          (status['isActive'] ?? false) ? '✅ Satış Açık' : '❌ Satış Kapalı',
        ], (status['isActive'] ?? false) ? Colors.teal : Colors.red),
      ],
    );
  }

  Widget _infoCard(String title, List<String> lines, Color accent) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: accent)),
            const SizedBox(height: 4),
            ...lines.map((l) => Text(l,
                style:
                const TextStyle(fontSize: 12, color: Color(0xFF445566)))),
          ],
        ),
      ),
    );
  }

  Widget _buildMaintenanceButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.build_circle_outlined),
        label: const Text('Bakım Kaydı Ekle'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () async {
          await machineRef.collection('maintenance_logs').add({
            'timestamp': FieldValue.serverTimestamp(),
            'performedBy': 'admin@system',
          });
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bakım kaydı başarıyla eklendi')),
            );
          }
        },
      ),
    );
  }

  Widget _buildExitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(
            _levelChanged ? Icons.timer_outlined : Icons.home_outlined),
        label: Text(
          _levelChanged
              ? 'Çıkış (90 dk Bekleme Başlayacak)'
              : 'Ana Sayfaya Dön',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor:
          _levelChanged ? Colors.orange.shade700 : AppColors.bzPrimaryDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        onPressed: _onWillPop,
      ),
    );
  }

  // ─── YARDIMCI METODLAR ────────────────────────────────────────────────────

  /// İçecek "Tam" seçildi:
  /// 1) Firestore'a maxVal yaz (ANİNDE)
  /// 2) _levelChanged = true işaretle (navigasyon çıkışa ertelendi)
  Future<void> _setLiquidFull(String path, String key, int maxVal) async {
    await machineRef.update({
      '$path.$key': maxVal,
      'levels.liquidBand': 'green',
    });
    setState(() => _levelChanged = true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
            '✅ Dolum kaydedildi. Çıkışta 90 dk bekleme başlayacak.'),
        backgroundColor: Colors.teal.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _updateIntValue(
      String path, String key, int newValue, int maxVal) async {
    await machineRef
        .update({'$path.$key': newValue.clamp(0, maxVal)});
  }

  Future<void> _enterManualValue(
      String path, String key, int maxVal) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Değer Gir'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '0 – $maxVal arası',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal')),
          ElevatedButton(
            onPressed: () async {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 0 || value > maxVal) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Değer 0 ile $maxVal arasında olmalı.')));
                return;
              }
              await machineRef.update({'$path.$key': value});
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}
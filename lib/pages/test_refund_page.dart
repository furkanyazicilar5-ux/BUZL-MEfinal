// test_refund_page.dart — Revize Edildi
import 'package:buzi_kiosk/pages/refund_animation_page.dart';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_info.dart';
import '../core/sales_data.dart';
import '../core/error_codes.dart';
import '../widgets/service_widgets/machine_service.dart';

class TestRefundPage extends StatelessWidget {
  final String title;
  final String volume;
  final String price;
  final int seconds;

  TestRefundPage({
    super.key,
    required this.title,
    required this.volume,
    required this.price,
    required this.seconds,
  });

  final _service = MachineService(machineId: kMachineId);

  Future<void> _logRefundAuto(
      String code, BuildContext context, String msg) async {
    final amountTl = double.tryParse(price) ?? 0.0;
    final amountMl =
        int.tryParse(volume.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    await SalesData.instance.logRefund(
      amountTl: amountTl,
      amountMl: amountMl,
      errorCode: code,
      cupType: title,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$msg ($title)'),
        backgroundColor: Colors.teal.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F1A),
      appBar: AppBar(
        title: const Text(
          'Test — İade Simülasyonu',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0D1F1A),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: Colors.white.withOpacity(0.12), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'İade Senaryosu Seç',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Test için bir hata türü seçin',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5), fontSize: 14),
              ),
              const SizedBox(height: 32),

              _TestButton(
                icon: Icons.ac_unit,
                label: 'Overfreeze Hatası',
                color: Colors.blue.shade400,
                onPressed: () async {
                  await _service.toggleMachineStatus(true);
                  await _logRefundAuto(
                    RefundErrorCodes.overfreeze,
                    context,
                    'Overfreeze log eklendi',
                  );
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RefundAnimationPage()),
                    );
                  }
                },
              ),
              const SizedBox(height: 14),

              _TestButton(
                icon: Icons.coffee_maker_outlined,
                label: 'Bardak Düşmedi',
                color: Colors.orange.shade400,
                onPressed: () async {
                  await _service.toggleMachineStatus(true);
                  await _logRefundAuto(
                    RefundErrorCodes.cupDrop,
                    context,
                    'Cup Drop log eklendi',
                  );
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RefundAnimationPage()),
                    );
                  }
                },
              ),
              const SizedBox(height: 14),

              _TestButton(
                icon: Icons.error_outline,
                label: 'Diğer Hata',
                color: Colors.red.shade400,
                onPressed: () async {
                  await _service.toggleMachineStatus(true);
                  await _logRefundAuto(
                    RefundErrorCodes.other,
                    context,
                    'Other Error log eklendi',
                  );
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RefundAnimationPage()),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _TestButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.15),
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.5), width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      label: Text(label,
          style:
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/i18n.dart';
import '../widgets/background_scaffold.dart';
import 'sales_closed_page.dart';

class RefundAnimationPage extends StatefulWidget {
  const RefundAnimationPage({super.key});

  @override
  State<RefundAnimationPage> createState() => _RefundAnimationPageState();
}

class _RefundAnimationPageState extends State<RefundAnimationPage> {
  bool _refundComplete = false;

  Timer? _completeTimer;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();

    // Sahada "iade ekranında takılı kalma" olmaması için:
    //  - 5 sn sonra tamamlandı UI
    //  - toplamda ~7 sn sonra (fallback) mutlaka SalesClosed'a geç
    _completeTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _refundComplete = true);
    });

    _navTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const SalesClosedPage(autoReturnHome: false),
        ),
        (route) => false,
      );
    });
  }

  @override
  void dispose() {
    _completeTimer?.cancel();
    _navTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundScaffold(
      appBar: AppBar(
        title: Text(trEn("İade", "Refund")),
        backgroundColor: Colors.transparent,
      ),
      child: Center(
        child: _refundComplete
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 64),
                  const SizedBox(height: 20),
                  Text(
                    trEn(
                      "Ücret iadesi başarı ile yapıldı",
                      "Refund completed successfully",
                    ),
                    style: const TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    trEn(
                      "Ürün doldurulurken bir hata ile karşılaşıldı.\nÜcret iadesi yapılıyor...",
                      "An error occurred while preparing the product.\nProcessing refund...",
                    ),
                    style: const TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }
}

// refund_animation_page.dart — Revize Edildi
import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/i18n.dart';
import '../widgets/background_scaffold.dart';
import 'sales_closed_page.dart';

class RefundAnimationPage extends StatefulWidget {
  const RefundAnimationPage({super.key});

  @override
  State<RefundAnimationPage> createState() => _RefundAnimationPageState();
}

class _RefundAnimationPageState extends State<RefundAnimationPage>
    with TickerProviderStateMixin {
  bool _refundComplete = false;
  Timer? _completeTimer;
  Timer? _navTimer;

  late AnimationController _iconCtrl;
  late Animation<double> _iconScale;
  late Animation<double> _iconOpacity;

  late AnimationController _checkCtrl;
  late Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();

    // Yükleniyor ikonunun giriş animasyonu
    _iconCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _iconScale = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _iconCtrl, curve: Curves.easeOutBack));
    _iconOpacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _iconCtrl, curve: Curves.easeIn));
    _iconCtrl.forward();

    // Tamamlandı check animasyonu
    _checkCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _checkScale = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _checkCtrl, curve: Curves.elasticOut));

    _completeTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _refundComplete = true);
      _checkCtrl.forward();
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
    _iconCtrl.dispose();
    _checkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundScaffold(
      extendBodyBehindAppBar: true,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: _refundComplete
              ? _buildComplete()
              : _buildProcessing(),
        ),
      ),
    );
  }

  Widget _buildProcessing() {
    return ScaleTransition(
      key: const ValueKey('processing'),
      scale: _iconScale,
      child: FadeTransition(
        opacity: _iconOpacity,
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
                color: Colors.white.withOpacity(0.2), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Uyarı ikonu
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orange.withOpacity(0.2),
                  border: Border.all(color: Colors.orange.shade400, width: 2),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 40),
              ),

              const SizedBox(height: 24),

              Text(
                trEn(
                  'Bir sorun oluştu',
                  'An error occurred',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                trEn(
                  'Ürün hazırlanırken bir hata ile karşılaşıldı.\nÜcret iadesi yapılıyor...',
                  'An error occurred while preparing.\nProcessing your refund...',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 18),
              ),

              const SizedBox(height: 32),

              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.bzPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComplete() {
    return ScaleTransition(
      key: const ValueKey('complete'),
      scale: _checkScale,
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
              color: Colors.white.withOpacity(0.2), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withOpacity(0.2),
                border: Border.all(color: Colors.green.shade400, width: 2),
              ),
              child: const Icon(Icons.check_circle,
                  color: Colors.green, size: 48),
            ),

            const SizedBox(height: 24),

            Text(
              trEn('İade Tamamlandı', 'Refund Completed'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              trEn(
                'Ücretiniz başarıyla iade edildi.',
                'Your payment has been refunded successfully.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7), fontSize: 18),
            ),

            const SizedBox(height: 24),

            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                trEn(
                  'Lütfen teknik servis ile iletişime geçin.',
                  'Please contact technical support.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55), fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'dart:async';
import 'package:flutter/material.dart';
import '../buzlime_integration/device_controller.dart';
import '../buzlime_integration/integration_entry.dart';
import '../core/app_colors.dart';
import '../core/i18n.dart';
import '../widgets/background_scaffold.dart';
import 'drink_page.dart';
import 'preparing_page.dart';
import 'refund_animation_page.dart';

/// PaymentPage — Revize Edildi
///
/// - Geri sayım çubuğu (30 sn)
/// - Temiz, modern kiosk UI
/// - Fiyat artık dışarıdan string olarak geliyor (Firestore'dan çekildi)
class PaymentPage extends StatefulWidget {
  final String drinkCode;
  final int sizeMl;
  final String volume;
  final String price;
  final int seconds;

  const PaymentPage({
    super.key,
    required this.drinkCode,
    required this.sizeMl,
    required this.volume,
    required this.price,
    required this.seconds,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage>
    with TickerProviderStateMixin {
  DeviceController? _ctrl;
  StreamSubscription? _sub;
  StreamSubscription? _telSub;
  bool _navigated = false;
  Timer? _paymentTimer;
  late AnimationController _countdownCtrl;
  int _remaining = 30;
  Timer? _uiCountdown;

  // Kart animasyonu
  late AnimationController _cardCtrl;
  late Animation<double> _cardScale;
  late Animation<double> _cardOpacity;

  @override
  void initState() {
    super.initState();

    // Giriş animasyonu
    _cardCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _cardScale =
        Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(
          parent: _cardCtrl,
          curve: Curves.easeOutBack,
        ));
    _cardOpacity =
        Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
          parent: _cardCtrl,
          curve: Curves.easeOut,
        ));
    _cardCtrl.forward();

    // Geri sayım çubuğu
    _countdownCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
      value: 1.0,
    )..reverse();

    _uiCountdown =
        Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {
            if (_remaining > 0) _remaining--;
          });
        });

    _paymentTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted || _navigated) return;
      _goHome();
    });

    _start();
  }

  Future<void> _start() async {
    try {
      final ctrl = getDeviceController();
      final ok = await ctrl.connect();
      if (!ok) {
        _goSalesClosed();
        return;
      }
      _ctrl = ctrl;

      _telSub = ctrl.telemetryStream.stream.listen((t) {
        if (_navigated) return;
        if (t.state == 'DISCONNECTED') _goSalesClosed();
      });

      await ctrl.startOrder(
        BuzlimeOrder(drinkCode: widget.drinkCode, sizeMl: widget.sizeMl),
      );

      _sub = ctrl.stepStream.stream.listen((step) {
        if (_navigated) return;
        if (step == PrepStep.paymentOk || step == PrepStep.preparing) {
          _goPreparing();
        } else if (step == PrepStep.error) {
          _goSalesClosed();
        }
      });
    } catch (_) {
      _goSalesClosed();
    }
  }

  void _goPreparing() {
    if (!mounted || _navigated) return;
    _navigated = true;
    _paymentTimer?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PreparingPage(
          drinkCode: widget.drinkCode,
          sizeMl: widget.sizeMl,
          volume: widget.volume,
          price: widget.price,
          seconds: widget.seconds,
        ),
      ),
    );
  }

  void _goSalesClosed() {
    if (!mounted || _navigated) return;
    _navigated = true;
    _paymentTimer?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RefundAnimationPage()),
    );
  }

  void _goHome() {
    if (!mounted || _navigated) return;
    _navigated = true;
    _paymentTimer?.cancel();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const DrinkPage()),
          (route) => false,
    );
  }

  @override
  void dispose() {
    _paymentTimer?.cancel();
    _uiCountdown?.cancel();
    _countdownCtrl.dispose();
    _cardCtrl.dispose();
    _sub?.cancel();
    _telSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drinkName = widget.drinkCode == 'LEMON'
        ? trEn('Limon', 'Lemon')
        : trEn('Portakal', 'Orange');

    return BackgroundScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 26),
          onPressed: _goHome,
        ),
      ),
      child: Center(
        child: ScaleTransition(
          scale: _cardScale,
          child: FadeTransition(
            opacity: _cardOpacity,
            child: Container(
              width: 520,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                    color: Colors.white.withOpacity(0.25), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  )
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 36, vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // İkon
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.bzPrimary.withOpacity(0.2),
                        border: Border.all(
                            color: AppColors.bzPrimary, width: 2),
                      ),
                      child: const Icon(
                        Icons.contactless_outlined,
                        color: Colors.white,
                        size: 46,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Başlık
                    Text(
                      trEn('Ödeme Bekleniyor', 'Waiting for Payment'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Ürün bilgisi
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$drinkName • ${widget.volume} • ${widget.price}₺',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w600),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Geri sayım çubuğu
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              trEn('Kalan süre', 'Time remaining'),
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 14),
                            ),
                            Text(
                              '$_remaining sn',
                              style: TextStyle(
                                color: _remaining <= 10
                                    ? Colors.red.shade300
                                    : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        AnimatedBuilder(
                          animation: _countdownCtrl,
                          builder: (_, __) => ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _countdownCtrl.value,
                              minHeight: 8,
                              color: _countdownCtrl.value < 0.33
                                  ? Colors.red.shade400
                                  : AppColors.bzPrimary,
                              backgroundColor:
                              Colors.white.withOpacity(0.15),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // Simülasyon butonu (MDB yokken)
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.bzPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: _goPreparing,
                        icon: const Icon(Icons.check_circle_outline,
                            size: 22),
                        label: Text(
                          trEn(
                              'Ödemeyi Simüle Et', 'Simulate Payment'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextButton(
                      onPressed: _goHome,
                      child: Text(
                        trEn('Vazgeç', 'Cancel'),
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
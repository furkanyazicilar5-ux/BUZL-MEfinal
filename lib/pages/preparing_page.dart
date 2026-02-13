// SPDX-License-Identifier: MIT
// PreparingPage — Buzlime sipariş takip ekranı
//
// Kural:
// - Başarılı satış (ORDER_DONE) -> satış kaydet -> Ana Menü
// - Hata (ORDER_ERROR / süreçte kopma) -> SalesClosedPage
// - USB/MCU yoksa (sipariş başlamadan) -> Ana Menü

import 'dart:async';

import 'package:flutter/material.dart';

import '../buzlime_integration/device_controller.dart';
import '../buzlime_integration/integration_entry.dart';
import '../core/sales_data.dart';
import '../widgets/background_scaffold.dart';
import '../home_page.dart';
import '../core/i18n.dart';
import 'refund_animation_page.dart';

class PreparingPage extends StatefulWidget {
  final String drinkCode; // 'LEMON' | 'ORANGE'
  final int sizeMl; // 300 | 400
  final String volume; // UI / sales
  final String price; // TL string
  final int seconds; // UI animasyon temposu (sadece görsel)

  const PreparingPage({
    super.key,
    required this.drinkCode,
    required this.sizeMl,
    required this.volume,
    required this.price,
    required this.seconds,
  });

  @override
  State<PreparingPage> createState() => _PreparingPageState();
}

class _PreparingPageState extends State<PreparingPage> with SingleTickerProviderStateMixin {
  DeviceController? _ctrl;
  StreamSubscription? _stepSub;
  StreamSubscription? _telSub;

  bool _finished = false;
  double _progress = 0.0;

  /// MCU'dan gelen son state (UI sadece bunu gösterir)
  String _mcuState = 'PREPARING';

  /// DELIVERY_OPEN / WAIT_PICKUP geldiğinde true olur.
  /// Bu modda timeout yoktur.
  bool _pickupMode = false;

  late final AnimationController _opacityController;
  late final Animation<double> _opacityAnimation;

  Timer? _uiTimer;
  Timer? _hardTimeout;
  int _elapsedMs = 0;
  late final int _totalMs;

  String get _drinkTitle {
    switch (widget.drinkCode) {
      case 'LEMON':
        return 'Limon';
      case 'ORANGE':
        return 'Portakal';
      default:
        return widget.drinkCode;
    }
  }

  @override
  void initState() {
    super.initState();

    _opacityController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _opacityAnimation = CurvedAnimation(
      parent: _opacityController,
      curve: Curves.easeInOut,
    );

    _totalMs = widget.seconds * 1000;

    // Sadece görsel animasyon: MCU event'leri gelmese bile % yavaşça ilerler.
    // Ama ASLA kendi kendine satışı tamamlamaz.
    _uiTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_finished) return;
      _elapsedMs += 50;
      if (_elapsedMs > _totalMs) _elapsedMs = _totalMs;
      final uiProg = _totalMs == 0 ? 0.0 : (_elapsedMs / _totalMs);
      // MCU'dan gelen progress daha büyükse onu koru
      if (uiProg > _progress) setState(() => _progress = uiProg);
    });

    _startOrderFlow();

    // Saha güvenliği: MCU bağlı ama süreç ilerlemiyorsa sonsuza kadar burada kalmayalım.
    // 90 sn (min) sonra veya widget.seconds + 30 sn sonra hata akışına düş.
    final hardSec = (widget.seconds + 30).clamp(90, 300);
    _hardTimeout = Timer(Duration(seconds: hardSec), () {
      if (!mounted) return;
      if (_finished) return;
      _goSalesClosed();
    });
  }

  Future<void> _startOrderFlow() async {
    try {
      final ctrl = getDeviceController();
      // CHECKLIST (PDF): START_ORDER yalnızca PaymentPage'te.
      // PreparingPage sadece mevcut bağlantıyı izler; bağlı değilse yeniden bağlanmayı dener.
      if (!ctrl.isConnected) {
        final ok = await ctrl.connect();
        if (!ok) {
          if (!mounted) return;
          _goSalesClosed();
          return;
        }
      }

      _ctrl = ctrl;

      _stepSub = ctrl.stepStream.stream.listen((step) async {
        if (_finished) return;
        if (step == PrepStep.waitPayment) {
          // ödeme bekleniyor
          setState(() {
            if (_progress < 0.10) _progress = 0.10;
          });
        } else if (step == PrepStep.paymentOk) {
          setState(() {
            if (_progress < 0.25) _progress = 0.25;
          });
        } else if (step == PrepStep.preparing) {
          setState(() {
            if (_progress < 0.35) _progress = 0.35;
          });
        } else if (step == PrepStep.done) {
          await _completeSaleAndGoHome();
        } else if (step == PrepStep.error) {
          _goSalesClosed();
        }
      });

      _telSub = ctrl.telemetryStream.stream.listen((t) {
        if (_finished) return;
        // Bağlantı koptuysa hata akışına düş
        if (t.state == 'DISCONNECTED') {
          _goSalesClosed();
          return;
        }

        // MCU state -> UI (son gelen state gösterilir)
        final st = (t.state ?? '').toString();
        if (st.isNotEmpty) {
          final up = st.toUpperCase();
          final isPickup = up.contains('DELIVERY_OPEN') || up.contains('WAIT_PICKUP');

          if (isPickup && !_pickupMode) {
            // PDF: DELIVERY_OPEN/WAIT_PICKUP modunda timeout yok.
            _pickupMode = true;
            _hardTimeout?.cancel();
            _hardTimeout = null;

            // Pickup ekranında progress animasyonu gereksiz; %100'e sabitle.
            _uiTimer?.cancel();
            _uiTimer = null;
            _elapsedMs = _totalMs;
            _progress = 1.0;
          }

          if (up != _mcuState) {
            setState(() => _mcuState = up);
          } else if (isPickup) {
            // Pickup mode'a ilk girişte setState kaçmış olabilir.
            setState(() {});
          }
        }

        // MCU progress gönderirse UI'ı yaklaştır
        final p = t.progress;
        if (p != null && p > _progress) {
          setState(() => _progress = p.clamp(0.0, 1.0));
        }
      });
    } catch (_) {
      // USB var ama akış başlarken problem -> SalesClosed
      if (!mounted) return;
      _goSalesClosed();
    }
  }

  void _goHomeNoSale() {
    if (_finished) return;
    _finished = true;
    _uiTimer?.cancel();
    _hardTimeout?.cancel();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  void _goSalesClosed() {
    if (_finished) return;
    _finished = true;
    _uiTimer?.cancel();
    _hardTimeout?.cancel();
    // PDF akışına göre: hata/problem -> RefundAnimation -> SalesClosed
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RefundAnimationPage()),
    );
  }

  Future<void> _completeSaleAndGoHome() async {
    if (_finished) return;
    _finished = true;
    _uiTimer?.cancel();
    _hardTimeout?.cancel();
    setState(() => _progress = 1.0);

    // Satışı kaydet
    try {
      await SalesData.instance.sellDrink(
        title: _drinkTitle,
        volume: widget.volume,
        priceTl: double.tryParse(widget.price) ?? 0.0,
      );
    } catch (_) {}

    if (!mounted) return;
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _hardTimeout?.cancel();
    _opacityController.dispose();
    _stepSub?.cancel();
    _telSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundScaffold(
      extendBodyBehindAppBar: true,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _opacityAnimation,
              child: Image.asset(
                'assets/buttons_new/product.png',
                height: 324,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 30),
            Text(
              _pickupMode
                  ? trEn('Lütfen ürününüzü alın', 'Please take your product')
                  : trEn('Ürününüz hazırlanıyor', 'Preparing your product'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),

            // Hazırlanıyor ekranında ürün bilgisi + progress göster.
            if (!_pickupMode) ...[
              Text(
                '$_drinkTitle • ${widget.volume}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                height: 120,
                width: 120,
                child: CircularProgressIndicator(
                  value: _progress.clamp(0.0, 1.0),
                  strokeWidth: 22,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF026B55)),
                  backgroundColor: const Color(0xFF4EF2C0),
                ),
              ),
              const SizedBox(height: 30),
              Text(
                "${(_progress * 100).toStringAsFixed(0)}%",
                style:
                    const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ] else ...[
              const SizedBox(height: 30),
              Text(
                trEn('Teslim kapağı açık', 'Delivery door is open'),
                style: const TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
import 'dart:async';

import 'package:flutter/material.dart';

import '../buzlime_integration/device_controller.dart';
import '../buzlime_integration/integration_entry.dart';
import '../core/i18n.dart';
import '../widgets/background_scaffold.dart';
import 'drink_page.dart';
import 'preparing_page.dart';
import 'refund_animation_page.dart';

/// Ödeme ekranı
///
/// Seri üretim akışı:
/// - Ürün seçildikten sonra buraya gelir.
/// - MCU ile bağlanır, START_ORDER atar.
/// - MCU ödeme (MDB) sürecini yönetir.
/// - PAYMENT_OK görülünce PreparingPage'e geçer.
/// - Her hata/başarısızlık -> RefundAnimation -> SalesClosed
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

class _PaymentPageState extends State<PaymentPage> {
  DeviceController? _ctrl;
  StreamSubscription? _sub;
  StreamSubscription? _telSub;
  bool _navigated = false;
  Timer? _paymentTimer;

  @override
  void initState() {
    super.initState();
    _start();

    // MDB henüz yokken ödeme simülasyonu için: 30 sn içinde ödeme alınmazsa ana menü.
    _paymentTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted || _navigated) return;
      _goHome();
    });
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

      // Telemetry: bağ koptuysa hemen hata akışı
      _telSub = ctrl.telemetryStream.stream.listen((t) {
        if (_navigated) return;
        if (t.state == 'DISCONNECTED') {
          _goSalesClosed();
        }
      });

      // Siparişi başlat
      await ctrl.startOrder(
        BuzlimeOrder(drinkCode: widget.drinkCode, sizeMl: widget.sizeMl),
      );

      // Step stream: ödeme ok -> preparing
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

    // Kiosk davranışı: ödeme alınmadı -> direkt ana menüye dön.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const DrinkPage()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _paymentTimer?.cancel();
    _sub?.cancel();
    _telSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ödeme timeout'u sabit 30sn olmalı; kullanıcı ekrana dokunsa bile uzatmıyoruz.
    // Bu yüzden InactivityWrapper yerine sabit Timer (initState) kullanıyoruz.
    return BackgroundScaffold(
      extendBodyBehindAppBar: true,
      appBar: null,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              trEn('Ödeme Bekleniyor', 'Waiting for payment'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${widget.volume} • ${widget.price}₺',
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 90,
              height: 90,
              child: CircularProgressIndicator(strokeWidth: 10),
            ),
            const SizedBox(height: 28),
            // MDB yokken test/simülasyon butonu
            SizedBox(
              width: 320,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _goPreparing,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(trEn('Ödemeyi Simüle Et', 'Simulate payment')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

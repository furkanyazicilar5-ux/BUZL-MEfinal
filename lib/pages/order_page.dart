// SPDX-License-Identifier: MIT
// order_page.dart — v2
//
// PaymentPage + PreparingPage + PickupPage birleşik sipariş sayfası.
//
// ── SalesClosed POLİTİKASI ──────────────────────────────────────────────────
//
//   SalesClosed'a geçiş GERÇEK bir arıza durumunu temsil eder.
//   Yanlışlıkla geçiş ihtimalini minimuma indirmek için:
//
//   1) Tek comm timer yerine ARDIŞIK HATA SAYACI kullanılır.
//      Tek bir timeout SalesClosed tetiklemez. MCU'dan üst üste
//      _kMaxCommMiss (3) kez mesaj gelmezse → SalesClosed.
//      Her gelen mesaj sayacı sıfırlar.
//
//   2) İlk bağlantı kurulamazsa bile hemen SalesClosed'a düşmez.
//      _kInitialConnectTimeout (15sn) boyunca yeniden denenir.
//
//   3) Pickup phase'inde comm timer ÇALIŞMAZ.
//      Müşteri bardağını alma süresi sınırsız.
//      MCU heartbeat gönderiyor olsa da, pickup'ta comm kopması
//      bardağı almayı engellememeli.
//
//   4) SalesClosed'a geçerken MCU'ya RESET komutu gönderilir.
//      Tüm motorlar durur, pompa kapanır, cihaz IDLE'a döner.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../buzlime_integration/device_controller.dart';
import '../buzlime_integration/integration_entry.dart';
import '../core/app_colors.dart';
import '../core/app_info.dart';
import '../core/log_buffer.dart';
import '../core/sales_data.dart';
import '../core/i18n.dart';
import '../widgets/background_scaffold.dart';
import '../home_page.dart';
import 'drink_page.dart';
import 'refund_animation_page.dart';
import 'sales_closed_page.dart';

// ═════════════════════════════════════════════════════════════════════════════
enum OrderPhase { connecting, payment, preparing, pickup, done }

// ═════════════════════════════════════════════════════════════════════════════
class OrderPage extends StatefulWidget {
  final String drinkCode;
  final int    sizeMl;
  final String volume;
  final String price;
  final int    seconds;

  const OrderPage({
    super.key,
    required this.drinkCode,
    required this.sizeMl,
    required this.volume,
    required this.price,
    required this.seconds,
  });

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> with TickerProviderStateMixin {

  // ── Phase ──────────────────────────────────────────────────────────────────
  OrderPhase _phase = OrderPhase.connecting;
  bool _finished = false;

  // ── Stream abonelikleri (TEK YERDE, HİÇ KOPMAZ) ──────────────────────────
  StreamSubscription? _stepSub;
  StreamSubscription? _telSub;

  // ═════════════════════════════════════════════════════════════════════════
  // SalesClosed KORUMA: Ardışık hata sayacı
  // ═════════════════════════════════════════════════════════════════════════
  //
  // Tek bir timeout SalesClosed tetiklemez. Her _kCommCheckInterval (5sn)
  // aralıkla kontrol yapılır. Son kontrolden beri MCU'dan mesaj geldiyse
  // _commMissCount sıfırlanır. Gelmediyse +1. Üst üste _kMaxCommMiss (3)
  // kez mesaj gelmezse → SalesClosed. Yani minimum 15sn sessizlik gerekir.
  //
  // Pickup phase'inde bu kontrol ÇALIŞMAZ — müşteri bardağını alana kadar
  // SalesClosed'a düşmez.
  static const int _kMaxCommMiss = 3;
  static const Duration _kCommCheckInterval = Duration(seconds: 5);
  static const Duration _kInitialConnectTimeout = Duration(seconds: 15);

  int _commMissCount = 0;
  bool _commEverReceived = false; // İlk MCU mesajı geldi mi
  Timer? _commCheckTimer;
  Timer? _initialConnectTimer;
  bool _gotMessageSinceLastCheck = false;

  // ── Telemetry polling (ek güvenlik) ────────────────────────────────────────
  Timer? _telemetryPollTimer;

  // ── Payment phase ─────────────────────────────────────────────────────────
  Timer? _paymentTimer;
  Timer? _paymentCountdownTimer;
  int _paymentRemaining = 30;
  late AnimationController _paymentCountdownCtrl;

  // ── Preparing phase ───────────────────────────────────────────────────────
  double _arduinoProgress = 0.0;
  double _targetProgress  = 0.0;
  bool   _arduinoSynced   = false;
  String _mcuState        = '';
  late AnimationController _barCtrl;
  late AnimationController _preparingPulseCtrl;
  late Animation<double>   _preparingPulseAnim;
  Timer? _fallbackTimer;
  int    _fallbackElapsedMs = 0;
  late final int _totalMs;

  // ── Pickup phase ──────────────────────────────────────────────────────────
  late AnimationController _pickupPulseCtrl;
  late Animation<double>   _pickupPulseScale;
  late Animation<double>   _pickupPulseOpacity;
  late AnimationController _burstCtrl;
  late AnimationController _bubbleCtrl;
  late List<_Bubble> _bubbles;

  // ── Getters ───────────────────────────────────────────────────────────────
  bool get _isLemon => widget.drinkCode == 'LEMON';
  String get _drinkTitle => _isLemon
      ? trEn('Limon', 'Lemon') : trEn('Portakal', 'Orange');
  Color get _accentColor => _isLemon
      ? const Color(0xFFD4E157) : const Color(0xFFFF8F00);

  String get _preparingLabel {
    final up = _mcuState.toUpperCase();
    if (up.contains('CUP') || up.contains('DISPENSE'))
      return trEn('Bardak hazırlanıyor', 'Preparing cup');
    if (up.contains('PUMP') || up.contains('FILL'))
      return trEn('Dolum yapılıyor', 'Filling drink');
    if (up.contains('VALVE'))
      return trEn('Vana açılıyor', 'Opening valve');
    return trEn('Ürününüz hazırlanıyor', 'Preparing your product');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    LogBuffer.I.add('[OrderPage] initState — ${widget.drinkCode} ${widget.sizeMl}ml');
    _totalMs = (widget.seconds * 1000).clamp(5000, 120000);

    _initPaymentAnimations();
    _initPreparingAnimations();
    _initPickupAnimations();

    // ── İlk bağlantı zamanaşımı (15sn) ──────────────────────────────────
    _initialConnectTimer = Timer(_kInitialConnectTimeout, () {
      if (!_finished && !_commEverReceived && mounted) {
        LogBuffer.I.add('[OrderPage] İlk bağlantı ${_kInitialConnectTimeout.inSeconds}sn timeout → SalesClosed');
        _goSalesClosed();
      }
    });

    // ── Ardışık hata sayacı: her 5sn kontrol ─────────────────────────────
    _commCheckTimer = Timer.periodic(_kCommCheckInterval, (_) {
      if (_finished || !mounted) return;
      // Pickup phase'inde kontrol YAPMA — müşteri bardak alıyor
      if (_phase == OrderPhase.pickup || _phase == OrderPhase.done) return;
      // İlk mesaj henüz gelmediyse _initialConnectTimer devrede
      if (!_commEverReceived) return;

      if (_gotMessageSinceLastCheck) {
        _commMissCount = 0;
        _gotMessageSinceLastCheck = false;
      } else {
        _commMissCount++;
        LogBuffer.I.add('[OrderPage] Comm miss #$_commMissCount/$_kMaxCommMiss (phase=$_phase)');
        if (_commMissCount >= _kMaxCommMiss) {
          LogBuffer.I.add('[OrderPage] $_kMaxCommMiss ardışık miss → SalesClosed');
          _goSalesClosed();
        }
      }
    });

    // ── Telemetry polling: her 2sn'de state kontrol ──────────────────────
    _telemetryPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_finished || !mounted) return;
      final ctrl = getDeviceController();
      final st = (ctrl.telemetry.state ?? '').toUpperCase();
      if (st.contains('DELIVERY_OPEN') || st.contains('WAIT_PICKUP')) {
        if (_phase != OrderPhase.pickup && _phase != OrderPhase.done) {
          LogBuffer.I.add('[OrderPage] Polling: state=$st → pickup');
          _setPhase(OrderPhase.pickup);
        }
      }
    });

    _startOrder();
  }

  void _initPaymentAnimations() {
    _paymentCountdownCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 30), value: 1.0,
    )..reverse();
  }

  void _initPreparingAnimations() {
    _barCtrl = AnimationController(
      vsync: this, value: 0.0,
      lowerBound: 0.0, upperBound: 1.0,
      duration: const Duration(milliseconds: 1),
    );
    _preparingPulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _preparingPulseAnim = Tween<double>(begin: 0.93, end: 1.0).animate(
      CurvedAnimation(parent: _preparingPulseCtrl, curve: Curves.easeInOut),
    );
  }

  void _initPickupAnimations() {
    _pickupPulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pickupPulseScale = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pickupPulseCtrl, curve: Curves.easeInOut),
    );
    _pickupPulseOpacity = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pickupPulseCtrl, curve: Curves.easeInOut),
    );
    _burstCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900),
    );
    _bubbleCtrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 6),
    )..repeat();
    final rng = math.Random();
    _bubbles = List.generate(12, (_) => _Bubble(
      x: rng.nextDouble(), size: 6.0 + rng.nextDouble() * 14.0,
      speed: 0.3 + rng.nextDouble() * 0.7, offset: rng.nextDouble(),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SİPARİŞ BAŞLAT + TEK LISTENER
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _startOrder() async {
    try {
      final ctrl = getDeviceController();
      LogBuffer.I.add('[OrderPage] connect() başlıyor...');
      if (!ctrl.isConnected) {
        if (!await ctrl.connect()) {
          LogBuffer.I.add('[OrderPage] connect() BAŞARISIZ — _initialConnectTimer bekliyor');
          return;
        }
      }
      LogBuffer.I.add('[OrderPage] Bağlantı OK → startOrder()');
      _onMcuMessage(); // Bağlantı başarılı = ilk sinyal

      await ctrl.startOrder(
        BuzlimeOrder(drinkCode: widget.drinkCode, sizeMl: widget.sizeMl),
      );
      LogBuffer.I.add('[OrderPage] startOrder() OK → payment phase');
      _setPhase(OrderPhase.payment);
      _startPaymentTimer();

      // ── TEK LISTENER — HİÇ CANCEL EDİLMEZ ────────────────────────────
      _stepSub = ctrl.stepStream.stream.listen((step) {
        if (_finished) return;
        _onMcuMessage();
        LogBuffer.I.add('[OrderPage] stepStream → $step (phase=$_phase)');

        switch (step) {
          case PrepStep.waitPayment:
            _setPhase(OrderPhase.payment);
            break;
          case PrepStep.paymentOk:
          case PrepStep.preparing:
            _cancelPaymentTimer();
            _setPhase(OrderPhase.preparing);
            break;
          case PrepStep.done:
            _setPhase(OrderPhase.pickup);
            _onOrderDone();
            break;
          case PrepStep.error:
            LogBuffer.I.add('[OrderPage] PrepStep.error — ignoring');
            break;
          default:
            break;
        }
      });

      _telSub = ctrl.telemetryStream.stream.listen((t) {
        if (_finished || !mounted) return;
        _onMcuMessage();

        final stRaw = (t.state ?? '').trim().toUpperCase();
        if (stRaw.isNotEmpty) {
          if (stRaw.contains('DELIVERY_OPEN') || stRaw.contains('WAIT_PICKUP')) {
            LogBuffer.I.add('[OrderPage] telemetry state=$stRaw → pickup');
            _cancelPaymentTimer();
            _setPhase(OrderPhase.pickup);
            return;
          }
          if (stRaw != _mcuState && mounted) {
            setState(() => _mcuState = stRaw);
          }
        }

        final p = t.progress;
        if (p != null) {
          final v = p.clamp(0.0, 1.0);
          if (v > _arduinoProgress) {
            _arduinoProgress = v;
            if (!_arduinoSynced && mounted) setState(() => _arduinoSynced = true);
            _animateBarTo(v);
          }
        }
      });

    } catch (e) {
      LogBuffer.I.add('[OrderPage] _startOrder HATA: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MCU MESAJ GELDİ — sayacı sıfırla
  // ═══════════════════════════════════════════════════════════════════════════
  void _onMcuMessage() {
    _gotMessageSinceLastCheck = true;
    if (!_commEverReceived) {
      _commEverReceived = true;
      _initialConnectTimer?.cancel();
      _initialConnectTimer = null;
      LogBuffer.I.add('[OrderPage] İlk MCU mesajı alındı — commCheck aktif');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE YÖNETİMİ
  // ═══════════════════════════════════════════════════════════════════════════
  void _setPhase(OrderPhase newPhase) {
    if (_finished || !mounted) return;
    if (newPhase.index <= _phase.index) return;
    LogBuffer.I.add('[OrderPage] phase: $_phase → $newPhase');
    setState(() => _phase = newPhase);

    if (newPhase == OrderPhase.preparing) {
      _startFallbackTimer();
    }
    if (newPhase == OrderPhase.pickup) {
      _burstCtrl.forward();
      _fallbackTimer?.cancel();
      // Pickup'ta comm kontrolü DURDUR — müşteri bardak alıyor
      // (_commCheckTimer çalışmaya devam eder ama pickup phase kontrolü yapar)
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAYMENT TIMER
  // ═══════════════════════════════════════════════════════════════════════════
  void _startPaymentTimer() {
    _paymentRemaining = 30;
    _paymentCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _phase != OrderPhase.payment) return;
      setState(() { if (_paymentRemaining > 0) _paymentRemaining--; });
    });
    _paymentTimer = Timer(const Duration(seconds: 30), () {
      if (_finished || _phase != OrderPhase.payment) return;
      LogBuffer.I.add('[OrderPage] Ödeme timeout → DrinkPage');
      _goHome();
    });
  }

  void _cancelPaymentTimer() {
    _paymentTimer?.cancel();
    _paymentCountdownTimer?.cancel();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FALLBACK PROGRESS TIMER
  // ═══════════════════════════════════════════════════════════════════════════
  void _startFallbackTimer() {
    _fallbackTimer?.cancel();
    _fallbackElapsedMs = 0;
    _fallbackTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_finished || _phase != OrderPhase.preparing) return;
      _fallbackElapsedMs += 300;
      if (_fallbackElapsedMs > _totalMs) _fallbackElapsedMs = _totalMs;
      _animateBarTo((_fallbackElapsedMs / _totalMs).clamp(0.0, 0.90));
    });
  }

  void _animateBarTo(double target) {
    final v = target.clamp(0.0, 1.0);
    if (v <= _targetProgress) return;
    _targetProgress = v;
    _barCtrl.animateTo(v,
        duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ORDER DONE
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _onOrderDone() async {
    if (_finished) return;
    _finished = true;
    LogBuffer.I.add('[OrderPage] ORDER_DONE → satış kaydediliyor');
    _cleanupTimers();

    try {
      await SalesData.instance.sellDrink(
        title: _drinkTitle, volume: widget.volume,
        priceTl: double.tryParse(widget.price) ?? 0.0,
        drinkCode: widget.drinkCode,
      );
    } catch (_) {}

    if (!mounted) return;
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const HomePage()), (_) => false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NAVİGASYON
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _goSalesClosed() async {
    if (_finished) return;
    _finished = true;
    LogBuffer.I.add('[OrderPage] >>> _goSalesClosed() — MCU RESET gönderiliyor');
    _cleanupTimers();

    // MCU'ya RESET gönder — tüm motorlar durur, cihaz IDLE'a döner
    try {
      await resetBuzlimeDevice();
      LogBuffer.I.add('[OrderPage] MCU RESET başarılı');
    } catch (e) {
      LogBuffer.I.add('[OrderPage] MCU RESET başarısız: $e');
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(
            builder: (_) => const SalesClosedPage(autoReturnHome: false)),
            (_) => false);
  }

  void _goRefund() {
    if (_finished) return;
    _finished = true;
    LogBuffer.I.add('[OrderPage] >>> _goRefund()');
    _cleanupTimers();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const RefundAnimationPage()),
            (_) => false);
  }

  void _goHome() {
    if (_finished) return;
    _finished = true;
    LogBuffer.I.add('[OrderPage] >>> _goHome()');
    _cleanupTimers();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const DrinkPage()), (_) => false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════
  void _cleanupTimers() {
    _commCheckTimer?.cancel();
    _initialConnectTimer?.cancel();
    _telemetryPollTimer?.cancel();
    _paymentTimer?.cancel();
    _paymentCountdownTimer?.cancel();
    _fallbackTimer?.cancel();
    _stepSub?.cancel();
    _telSub?.cancel();
  }

  @override
  void dispose() {
    _cleanupTimers();
    _paymentCountdownCtrl.dispose();
    _barCtrl.dispose();
    _preparingPulseCtrl.dispose();
    _pickupPulseCtrl.dispose();
    _burstCtrl.dispose();
    _bubbleCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return BackgroundScaffold(
      extendBodyBehindAppBar: true,
      appBar: _phase == OrderPhase.payment
          ? AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 26),
          onPressed: _goHome,
        ),
      )
          : null,
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: _buildPhase(),
        ),
      ),
    );
  }

  Widget _buildPhase() {
    switch (_phase) {
      case OrderPhase.connecting: return _buildConnecting();
      case OrderPhase.payment:    return _buildPayment();
      case OrderPhase.preparing:  return _buildPreparing();
      case OrderPhase.pickup:     return _buildPickup();
      case OrderPhase.done:       return const SizedBox.shrink();
    }
  }

  // ── CONNECTING ─────────────────────────────────────────────────────────────
  Widget _buildConnecting() {
    return Center(
      key: const ValueKey('connecting'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 56, height: 56,
              child: CircularProgressIndicator(strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.bzPrimary))),
          const SizedBox(height: 24),
          Text(trEn('Bağlanıyor...', 'Connecting...'),
              style: TextStyle(color: Colors.white.withOpacity(0.8),
                  fontSize: 22, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── PAYMENT ────────────────────────────────────────────────────────────────
  Widget _buildPayment() {
    return Center(
      key: const ValueKey('payment'),
      child: Container(
        width: 520,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3),
              blurRadius: 30, offset: const Offset(0, 12))],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: AppColors.bzPrimary.withOpacity(0.2),
                    border: Border.all(color: AppColors.bzPrimary, width: 2)),
                child: const Icon(Icons.contactless_outlined,
                    color: Colors.white, size: 46),
              ),
              const SizedBox(height: 24),
              Text(trEn('Ödeme Bekleniyor', 'Waiting for Payment'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 38,
                      fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                    '$_drinkTitle • ${widget.volume} • ${widget.price}₺',
                    style: const TextStyle(color: Colors.white, fontSize: 22,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(trEn('Kalan süre', 'Time remaining'),
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
                  Text('$_paymentRemaining sn',
                      style: TextStyle(
                          color: _paymentRemaining <= 10 ? Colors.red.shade300 : Colors.white,
                          fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedBuilder(
                animation: _paymentCountdownCtrl,
                builder: (_, __) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: _paymentCountdownCtrl.value, minHeight: 8,
                      color: _paymentCountdownCtrl.value < 0.33
                          ? Colors.red.shade400 : AppColors.bzPrimary,
                      backgroundColor: Colors.white.withOpacity(0.15)),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity, height: 58,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.bzPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0),
                  onPressed: () {
                    _cancelPaymentTimer();
                    _setPhase(OrderPhase.preparing);
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 22),
                  label: Text(trEn('Ödemeyi Simüle Et', 'Simulate Payment'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _goHome,
                child: Text(trEn('Vazgeç', 'Cancel'),
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── PREPARING ──────────────────────────────────────────────────────────────
  Widget _buildPreparing() {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    return Column(
      key: const ValueKey('preparing'),
      children: [
        SizedBox(height: h * 0.04),
        ScaleTransition(scale: _preparingPulseAnim,
            child: _ProductImage(height: h * 0.26)),
        SizedBox(height: h * 0.028),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(_preparingLabel,
              key: ValueKey(_preparingLabel), textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white,
                  fontSize: (w * 0.052).clamp(24.0, 42.0),
                  fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        ),
        const SizedBox(height: 6),
        Text('$_drinkTitle  •  ${widget.volume}',
            style: TextStyle(color: Colors.white.withOpacity(0.65),
                fontSize: (w * 0.026).clamp(15.0, 22.0), fontWeight: FontWeight.w500)),
        const Spacer(),
        Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.07),
            child: _ProgressSection(barCtrl: _barCtrl, arduinoSynced: _arduinoSynced)),
        SizedBox(height: h * 0.07),
      ],
    );
  }

  // ── PICKUP ─────────────────────────────────────────────────────────────────
  Widget _buildPickup() {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    return Stack(
      key: const ValueKey('pickup'),
      children: [
        AnimatedBuilder(animation: _bubbleCtrl,
            builder: (_, __) => CustomPaint(size: MediaQuery.of(context).size,
                painter: _BubblePainter(bubbles: _bubbles,
                    progress: _bubbleCtrl.value,
                    color: _accentColor.withOpacity(0.18)))),
        Center(child: AnimatedBuilder(animation: _burstCtrl,
            builder: (_, __) {
              final t = _burstCtrl.value;
              return Transform.scale(scale: 0.5 + t * 2.5,
                  child: Container(width: 120, height: 120,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                          border: Border.all(
                              color: _accentColor.withOpacity((1.0 - t).clamp(0.0, 1.0) * 0.5),
                              width: 3))));
            })),
        Center(
          child: AnimatedBuilder(animation: _pickupPulseScale,
            builder: (_, child) => Transform.scale(
                scale: _pickupPulseScale.value,
                child: Opacity(opacity: _pickupPulseOpacity.value, child: child)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/buttons_new/product.png',
                    height: h * 0.22, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(Icons.local_drink_rounded,
                        size: h * 0.14, color: Colors.white.withOpacity(0.8))),
                SizedBox(height: h * 0.04),
                Text(trEn('BuzLime Hazır!', 'BuzLime Ready!'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white,
                        fontSize: (w * 0.070).clamp(32.0, 58.0),
                        fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1.15,
                        shadows: [Shadow(color: _accentColor.withOpacity(0.4), blurRadius: 24)])),
                SizedBox(height: h * 0.012),
                Text(trEn('Afiyet Olsun', 'Enjoy Your Drink'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.85),
                        fontSize: (w * 0.038).clamp(18.0, 30.0),
                        fontWeight: FontWeight.w500, letterSpacing: 1.5)),
                SizedBox(height: h * 0.05),
                _PickupBadge(color: _accentColor, w: w),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// YARDIMCI WİDGET'LAR
// ═════════════════════════════════════════════════════════════════════════════

class _ProductImage extends StatelessWidget {
  final double height;
  const _ProductImage({required this.height});
  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/buttons_new/product.png',
        height: height, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(Icons.local_drink_rounded,
            size: height * 0.6, color: Colors.white.withOpacity(0.8)));
  }
}

class _ProgressSection extends StatelessWidget {
  final AnimationController barCtrl;
  final bool arduinoSynced;
  const _ProgressSection({required this.barCtrl, required this.arduinoSynced});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: barCtrl, builder: (_, __) {
      final val = barCtrl.value;
      final pct = (val * 100).toInt().clamp(0, 100);
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$pct%', style: const TextStyle(color: Colors.white,
              fontSize: 32, fontWeight: FontWeight.bold)),
          _ArduinoBadge(synced: arduinoSynced),
        ]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(14),
            child: LinearProgressIndicator(value: val, minHeight: 20,
                valueColor: AlwaysStoppedAnimation<Color>(
                    arduinoSynced ? AppColors.bzPrimary : const Color(0xFF026B55)),
                backgroundColor: const Color(0xFF4EF2C0).withOpacity(0.30))),
        const SizedBox(height: 16),
        _StepRow(progress: val),
      ]);
    });
  }
}

class _ArduinoBadge extends StatelessWidget {
  final bool synced;
  const _ArduinoBadge({required this.synced});
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
          color: synced ? AppColors.bzPrimary.withOpacity(0.22) : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: synced
              ? AppColors.bzPrimary.withOpacity(0.65) : Colors.white.withOpacity(0.18))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(synced ? Icons.usb_rounded : Icons.hourglass_top_rounded,
            color: synced ? Colors.white : Colors.white54, size: 13),
        const SizedBox(width: 5),
        Text(synced ? 'Arduino' : trEn('Bekleniyor', 'Waiting'),
            style: TextStyle(color: synced ? Colors.white : Colors.white54,
                fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  final double progress;
  const _StepRow({required this.progress});
  static const _steps = [
    (icon: Icons.local_drink_outlined,  tr: 'Bardak',     en: 'Cup',  at: 0.30),
    (icon: Icons.water_drop_outlined,   tr: 'Dolum',      en: 'Fill', at: 0.65),
    (icon: Icons.check_circle_outline,  tr: 'Tamamlandı', en: 'Done', at: 1.00),
  ];
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center,
        children: _steps.map((s) {
          final done = progress >= s.at;
          final active = !done && progress >= (s.at - 0.35).clamp(0.0, 1.0);
          return Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                    duration: const Duration(milliseconds: 350), curve: Curves.easeOut,
                    width: 44, height: 44,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: done ? AppColors.bzPrimary
                            : active ? AppColors.bzPrimary.withOpacity(0.28)
                            : Colors.white.withOpacity(0.10),
                        border: Border.all(
                            color: done ? AppColors.bzPrimary
                                : active ? AppColors.bzPrimary.withOpacity(0.6)
                                : Colors.white.withOpacity(0.20), width: 2)),
                    child: Icon(s.icon,
                        color: done ? Colors.white : active ? Colors.white70 : Colors.white30,
                        size: 20)),
                const SizedBox(height: 5),
                Text(trEn(s.tr, s.en),
                    style: TextStyle(
                        color: done ? Colors.white
                            : active ? Colors.white60 : Colors.white.withOpacity(0.30),
                        fontSize: 12, fontWeight: done ? FontWeight.bold : FontWeight.normal)),
              ]));
        }).toList());
  }
}

class _PickupBadge extends StatelessWidget {
  final Color color;
  final double w;
  const _PickupBadge({required this.color, required this.w});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
          color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.50), width: 2)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.shopping_bag_outlined, color: color, size: 28),
        const SizedBox(width: 12),
        Text(trEn('Bardağınızı alabilirsiniz', 'You may take your cup'),
            style: TextStyle(color: Colors.white,
                fontSize: (w * 0.026).clamp(14.0, 22.0), fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _Bubble {
  final double x, size, speed, offset;
  const _Bubble({required this.x, required this.size, required this.speed, required this.offset});
}

class _BubblePainter extends CustomPainter {
  final List<_Bubble> bubbles;
  final double progress;
  final Color color;
  _BubblePainter({required this.bubbles, required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final b in bubbles) {
      final t = ((progress * b.speed + b.offset) % 1.0);
      final y = size.height * (1.0 - t);
      final x = b.x * size.width + math.sin(t * math.pi * 4) * 18;
      final scale = t < 0.8 ? 1.0 : (1.0 - t) / 0.2;
      canvas.drawCircle(Offset(x, y), b.size * scale * 0.5, paint);
    }
  }
  @override
  bool shouldRepaint(covariant _BubblePainter old) => true;
}
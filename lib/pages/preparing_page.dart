// SPDX-License-Identifier: MIT
// preparing_page.dart — v5
//
// YENİLİKLER:
//   - Arduino DELIVERY_OPEN event'i → Pickup ekranı ("Buzlime Hazır!" / "İçeceğiniz Hazır!")
//   - İçeceğe göre farklı mesaj: LEMON → "Buzlime Hazır! Afiyet olsun 🍋"
//                                 ORANGE → "İçeceğiniz Hazır! Afiyet olsun 🍊"
//   - Pickup ekranında animasyonlu kutlama efekti (scale + fade pulse)
//   - "Bardağınızı alın" ikinci satır talimatı
//   - ORDER_DONE gelince satış kaydedilip HomePage'e geçiliyor

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../buzlime_integration/device_controller.dart';
import '../buzlime_integration/integration_entry.dart';
import '../core/app_colors.dart';
import '../core/sales_data.dart';
import '../core/i18n.dart';
import '../widgets/background_scaffold.dart';
import '../home_page.dart';
import 'sales_closed_page.dart';

// ═════════════════════════════════════════════════════════════════════════════
class PreparingPage extends StatefulWidget {
  final String drinkCode; // 'LEMON' | 'ORANGE'
  final int    sizeMl;    // 300 | 400
  final String volume;    // '300ml' | '400ml'
  final String price;     // '30' | '45'
  final int    seconds;   // tahmini hazırlık süresi

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

// ─── TickerProviderStateMixin: birden fazla AnimationController için zorunlu ──
class _PreparingPageState extends State<PreparingPage>
    with TickerProviderStateMixin {

  // ── Bağlantı ────────────────────────────────────────────────────────────────
  StreamSubscription? _stepSub;
  StreamSubscription? _telSub;
  bool _finished = false;

  // ── Progress durumu ──────────────────────────────────────────────────────────
  double _arduinoProgress = 0.0;
  double _targetProgress  = 0.0;
  bool   _arduinoSynced   = false;
  bool   _pickupMode      = false; // DELIVERY_OPEN geldi
  String _mcuState        = '';

  // ── AnimationController 1: ilerleme çubuğu ──────────────────────────────────
  late final AnimationController _barCtrl;

  // ── AnimationController 2: ikon nabzı (hazırlık sırasında) ──────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  // ── AnimationController 3: pickup kutlama efekti ────────────────────────────
  late final AnimationController _celebCtrl;
  late final Animation<double>   _celebScale;
  late final Animation<double>   _celebOpacity;

  // ── Fallback timer ───────────────────────────────────────────────────────────
  Timer? _fallbackTimer;
  Timer? _hardTimeout;
  int    _fallbackElapsedMs = 0;
  late final int _totalMs;
  late final int _hardSec;

  // ── Getters ──────────────────────────────────────────────────────────────────
  bool get _isLemon => widget.drinkCode == 'LEMON';

  String get _drinkTitle => _isLemon
      ? trEn('Limon', 'Lemon')
      : trEn('Portakal', 'Orange');

  /// Ana başlık mesajı — pickup modunda içeceğe özgü
  String get _headlineText {
    if (!_pickupMode) return _preparingLabel;
    return _isLemon
        ? trEn('Buzlime Hazır! 🍋', 'Buzlime Ready! 🍋')
        : trEn('İçeceğiniz Hazır! 🍊', 'Your Drink is Ready! 🍊');
  }

  /// İkinci satır talimatı
  String get _subtitleText {
    if (!_pickupMode) return '$_drinkTitle  •  ${widget.volume}';
    return trEn('Bardağınızı alın, afiyet olsun!', 'Please take your cup, enjoy!');
  }

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
    _totalMs = (widget.seconds * 1000).clamp(5000, 120000);

    // ── İlerleme çubuğu ────────────────────────────────────────────────────
    _barCtrl = AnimationController(
      vsync: this,
      value: 0.0,
      lowerBound: 0.0,
      upperBound: 1.0,
      duration: const Duration(milliseconds: 1),
    );

    // ── Hazırlık nabzı ──────────────────────────────────────────────────────
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.93, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // ── Pickup kutlama animasyonu ────────────────────────────────────────────
    // Döngüsel: scale 0.95 → 1.05 → 0.95 + hafif opacity titremesi
    _celebCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _celebScale = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _celebCtrl, curve: Curves.easeInOut),
    );
    _celebOpacity = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _celebCtrl, curve: Curves.easeInOut),
    );

    // ── Fallback timer ──────────────────────────────────────────────────────
    _fallbackTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_finished || _pickupMode) return;
      _fallbackElapsedMs += 300;
      if (_fallbackElapsedMs > _totalMs) _fallbackElapsedMs = _totalMs;
      final fp = (_fallbackElapsedMs / _totalMs).clamp(0.0, 0.90);
      _animateTo(fp);
    });

    // ── Hard timeout ────────────────────────────────────────────────────────
    // Arduino'dan event geldikçe sıfırlanır (_resetHardTimeout).
    // İlk değer: Arduino senaryosu + pickup bekleme süresini kapsamalı.
    _hardSec = (widget.seconds + 60).clamp(120, 300);
    _hardTimeout = Timer(Duration(seconds: _hardSec), () {
      if (!_finished && mounted) _goSalesClosed();
    });

    _startOrderFlow();
  }

  // ── Smooth progress (setState YOK) ─────────────────────────────────────────
  void _animateTo(double target) {
    final v = target.clamp(0.0, 1.0);
    if (v <= _targetProgress) return;
    _targetProgress = v;
    _barCtrl.animateTo(v,
        duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
  }

  // ── Arduino event geldiğinde hard timeout'u sıfırla ─────────────────────────
  // Arduino event göndermeye devam ettiği sürece timeout tetiklenmez.
  // Event kesilirse (gerçek hata/kopma) timeout devreye girer.
  void _resetHardTimeout() {
    if (_finished || _pickupMode) return;
    _hardTimeout?.cancel();
    _hardTimeout = Timer(Duration(seconds: _hardSec), () {
      if (!_finished && mounted) _goSalesClosed();
    });
  }

  // ── Arduino bağlantı akışı ─────────────────────────────────────────────────
  Future<void> _startOrderFlow() async {
    try {
      final ctrl = getDeviceController();
      if (!ctrl.isConnected) {
        if (!await ctrl.connect()) {
          if (mounted) _goSalesClosed();
          return;
        }
      }

      // PrepStep stream
      _stepSub = ctrl.stepStream.stream.listen((step) async {
        if (_finished) return;
        switch (step) {
          case PrepStep.waitPayment: _animateTo(0.08); break;
          case PrepStep.paymentOk:  _animateTo(0.22); break;
          case PrepStep.preparing:  _animateTo(0.35); break;
          case PrepStep.done:       await _completeSale(); break;
          case PrepStep.error:      _goSalesClosed(); break;
          default: break;
        }
      });

      // Telemetry stream
      _telSub = ctrl.telemetryStream.stream.listen((t) {
        if (_finished || !mounted) return;
        if (t.state == 'DISCONNECTED') { _goSalesClosed(); return; }

        final stRaw = (t.state ?? '').trim().toUpperCase();

        // Arduino hâlâ event gönderiyor → hard timeout'u sıfırla
        if (stRaw.isNotEmpty) _resetHardTimeout();

        if (stRaw.isNotEmpty) {
          // ── DELIVERY_OPEN → Pickup modu ──────────────────────────────────
          if ((stRaw.contains('DELIVERY_OPEN') || stRaw.contains('WAIT_PICKUP'))
              && !_pickupMode) {
            _fallbackTimer?.cancel();
            _hardTimeout?.cancel();
            _animateTo(1.0);
            _pulseCtrl.stop();
            _celebCtrl.repeat(reverse: true); // kutlama başlat
            setState(() => _pickupMode = true);
            return;
          }
          if (stRaw != _mcuState) setState(() => _mcuState = stRaw);
        }

        // Arduino progress
        final p = t.progress;
        if (p != null) {
          final v = p.clamp(0.0, 1.0);
          if (v > _arduinoProgress) {
            _arduinoProgress = v;
            if (!_arduinoSynced) setState(() => _arduinoSynced = true);
            _animateTo(v);
          }
        }
      });

    } catch (_) {
      if (mounted && !_finished) _goSalesClosed();
    }
  }

  // ── Hata → SalesClosedPage ──────────────────────────────────────────────────
  void _goSalesClosed() {
    if (_finished) return;
    _finished = true;
    _cleanup();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
          builder: (_) => const SalesClosedPage(autoReturnHome: false)),
          (_) => false,
    );
  }

  // ── ORDER_DONE → satış kaydet → HomePage ────────────────────────────────────
  Future<void> _completeSale() async {
    if (_finished) return;
    _finished = true;
    _cleanup();
    _animateTo(1.0);

    try {
      await SalesData.instance.sellDrink(
        title: _drinkTitle,
        volume: widget.volume,
        priceTl: double.tryParse(widget.price) ?? 0.0,
        drinkCode: widget.drinkCode,
      );
    } catch (_) {}

    if (!mounted) return;
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
          (_) => false,
    );
  }

  void _cleanup() {
    _fallbackTimer?.cancel();
    _hardTimeout?.cancel();
    _stepSub?.cancel();
    _telSub?.cancel();
  }

  @override
  void dispose() {
    _cleanup();
    _barCtrl.dispose();
    _pulseCtrl.dispose();
    _celebCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;

    return BackgroundScaffold(
      extendBodyBehindAppBar: true,
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: _pickupMode
              ? _PickupScreen(
            key: const ValueKey('pickup'),
            headline: _headlineText,
            subtitle: _subtitleText,
            isLemon: _isLemon,
            celebScale: _celebScale,
            celebOpacity: _celebOpacity,
            h: h,
            w: w,
          )
              : _PreparingScreen(
            key: const ValueKey('preparing'),
            statusLabel: _preparingLabel,
            drinkSubtitle: '$_drinkTitle  •  ${widget.volume}',
            barCtrl: _barCtrl,
            pulseAnim: _pulseAnim,
            arduinoSynced: _arduinoSynced,
            h: h,
            w: w,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Hazırlık ekranı
// ═════════════════════════════════════════════════════════════════════════════
class _PreparingScreen extends StatelessWidget {
  final String statusLabel;
  final String drinkSubtitle;
  final AnimationController barCtrl;
  final Animation<double> pulseAnim;
  final bool arduinoSynced;
  final double h, w;

  const _PreparingScreen({
    super.key,
    required this.statusLabel,
    required this.drinkSubtitle,
    required this.barCtrl,
    required this.pulseAnim,
    required this.arduinoSynced,
    required this.h,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: h * 0.04),

        // İkon
        ScaleTransition(
          scale: pulseAnim,
          child: _ProductImage(height: h * 0.26),
        ),

        SizedBox(height: h * 0.028),

        // Durum başlığı
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            statusLabel,
            key: ValueKey(statusLabel),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: (w * 0.052).clamp(24.0, 42.0),
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),

        const SizedBox(height: 6),

        Text(
          drinkSubtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.65),
            fontSize: (w * 0.026).clamp(15.0, 22.0),
            fontWeight: FontWeight.w500,
          ),
        ),

        const Spacer(),

        // Progress
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.07),
          child: _ProgressSection(
            barCtrl: barCtrl,
            arduinoSynced: arduinoSynced,
          ),
        ),

        SizedBox(height: h * 0.07),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Pickup ekranı — "Buzlime Hazır!" / "İçeceğiniz Hazır!"
// ═════════════════════════════════════════════════════════════════════════════
class _PickupScreen extends StatelessWidget {
  final String headline;
  final String subtitle;
  final bool isLemon;
  final Animation<double> celebScale;
  final Animation<double> celebOpacity;
  final double h, w;

  const _PickupScreen({
    super.key,
    required this.headline,
    required this.subtitle,
    required this.isLemon,
    required this.celebScale,
    required this.celebOpacity,
    required this.h,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2),

        // ── Animasyonlu ikon ──────────────────────────────────────────────────
        AnimatedBuilder(
          animation: celebScale,
          builder: (_, child) => Transform.scale(
            scale: celebScale.value,
            child: Opacity(
              opacity: celebOpacity.value,
              child: child,
            ),
          ),
          child: _ProductImage(height: h * 0.28),
        ),

        SizedBox(height: h * 0.04),

        // ── Ana mesaj ─────────────────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.08),
          child: Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: (w * 0.060).clamp(28.0, 52.0),
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.2,
            ),
          ),
        ),

        SizedBox(height: h * 0.022),

        // ── Alt mesaj ─────────────────────────────────────────────────────────
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.80),
            fontSize: (w * 0.030).clamp(16.0, 26.0),
            fontWeight: FontWeight.w500,
          ),
        ),

        SizedBox(height: h * 0.05),

        // ── Ikon ve renk bandı ────────────────────────────────────────────────
        _PickupBadge(isLemon: isLemon, w: w),

        const Spacer(flex: 3),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pickup renkli rozet
// ─────────────────────────────────────────────────────────────────────────────
class _PickupBadge extends StatelessWidget {
  final bool isLemon;
  final double w;
  const _PickupBadge({required this.isLemon, required this.w});

  @override
  Widget build(BuildContext context) {
    final color = isLemon
        ? const Color(0xFFD4E157)   // limon sarısı tonu
        : const Color(0xFFFF8F00);  // portakal turuncusu

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.55), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(
            trEn('Bardağınızı alabilirsiniz', 'You may take your cup'),
            style: TextStyle(
              color: Colors.white,
              fontSize: (w * 0.026).clamp(14.0, 22.0),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Ürün görseli — asset yoksa ikon fallback
// ═════════════════════════════════════════════════════════════════════════════
class _ProductImage extends StatelessWidget {
  final double height;
  const _ProductImage({required this.height});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/buttons_new/product.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.local_drink_rounded,
        size: height * 0.6,
        color: Colors.white.withOpacity(0.8),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Progress bölgesi
// ═════════════════════════════════════════════════════════════════════════════
class _ProgressSection extends StatelessWidget {
  final AnimationController barCtrl;
  final bool arduinoSynced;

  const _ProgressSection({
    required this.barCtrl,
    required this.arduinoSynced,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: barCtrl,
      builder: (_, __) {
        final val = barCtrl.value;
        final pct = (val * 100).toInt().clamp(0, 100);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$pct%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _ArduinoBadge(synced: arduinoSynced),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: LinearProgressIndicator(
                value: val,
                minHeight: 20,
                valueColor: AlwaysStoppedAnimation<Color>(
                  arduinoSynced
                      ? AppColors.bzPrimary
                      : const Color(0xFF026B55),
                ),
                backgroundColor:
                const Color(0xFF4EF2C0).withOpacity(0.30),
              ),
            ),
            const SizedBox(height: 16),
            _StepRow(progress: val),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Arduino senkron rozeti
// ─────────────────────────────────────────────────────────────────────────────
class _ArduinoBadge extends StatelessWidget {
  final bool synced;
  const _ArduinoBadge({required this.synced});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: synced
            ? AppColors.bzPrimary.withOpacity(0.22)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: synced
              ? AppColors.bzPrimary.withOpacity(0.65)
              : Colors.white.withOpacity(0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            synced ? Icons.usb_rounded : Icons.hourglass_top_rounded,
            color: synced ? Colors.white : Colors.white54,
            size: 13,
          ),
          const SizedBox(width: 5),
          Text(
            synced ? 'Arduino' : trEn('Bekleniyor', 'Waiting'),
            style: TextStyle(
              color: synced ? Colors.white : Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Adım göstergesi
// ─────────────────────────────────────────────────────────────────────────────
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _steps.map((s) {
        final done   = progress >= s.at;
        final active = !done && progress >= (s.at - 0.35).clamp(0.0, 1.0);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? AppColors.bzPrimary
                      : active
                      ? AppColors.bzPrimary.withOpacity(0.28)
                      : Colors.white.withOpacity(0.10),
                  border: Border.all(
                    color: done
                        ? AppColors.bzPrimary
                        : active
                        ? AppColors.bzPrimary.withOpacity(0.6)
                        : Colors.white.withOpacity(0.20),
                    width: 2,
                  ),
                ),
                child: Icon(s.icon,
                    color: done ? Colors.white : active ? Colors.white70 : Colors.white30,
                    size: 20),
              ),
              const SizedBox(height: 5),
              Text(
                trEn(s.tr, s.en),
                style: TextStyle(
                  color: done
                      ? Colors.white
                      : active ? Colors.white60 : Colors.white.withOpacity(0.30),
                  fontSize: 12,
                  fontWeight: done ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
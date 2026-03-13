// SPDX-License-Identifier: MIT
// preparing_page.dart — v4
//
// ─── HATA ANALİZİ & DÜZELTMELER ─────────────────────────────────────────────
//
// KIRMIZI EKRAN NEDENLERİ:
//
// 1. SingleTickerProviderStateMixin + 2 AnimationController
//    → Flutter yalnızca 1 ticker tahsis eder; ikinci controller oluşturulunca
//      "A Ticker was created by _PreparingPageState but was never disposed" /
//      "Too many tickers" assertion hatası verir → kırmızı ekran.
//    DÜZELTME: TickerProviderStateMixin kullanıldı.
//
// 2. _uiTimer her 50 ms setState() çağırıyor
//    → Frame pipeline dolu olduğunda "setState() called during build"
//      veya "setState() after dispose()" exception → kırmızı ekran.
//    DÜZELTME: Timer tamamen kaldırıldı. Progress yalnızca
//    AnimationController.animateTo() ile yumuşatılıyor (setState yok).
//
// 3. connect() çift çağrısı (PaymentPage + PreparingPage)
//    → UsbCdcTransport zaten açıkken tekrar open() çağrılır,
//      _rxCtrl kapalıysa "Bad state: Cannot add to a closed stream" → crash.
//    DÜZELTME: isConnected kontrolü korundu; connect() sadece gerekirse çağrılır.
//    Ayrıca UsbCdcTransport.close() → _rxCtrl.close() zinciri kırılmaz.
//
// 4. Image.asset() → asset yoksa "Unable to load asset" exception
//    → kırmızı ekran. DÜZELTME: errorBuilder eklendi; asset bulunamazsa
//      yedek ikon gösterilir, uygulama çökmez.
//
// ─── ARDUINO PARALEL PROGRESS ────────────────────────────────────────────────
//
//  Arduino ORDER_STATUS event'indeki progress (0.0–1.0) doğrudan bara yansır.
//  Arduino sessizse _FallbackTicker yavaşça ilerler (max %90 tavanı).
//  ORDER_DONE → %100 → 2 sn bekle → HomePage.
//  Her hata → SalesClosedPage(autoReturnHome: false).
//
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';

import '../buzlime_integration/device_controller.dart';
import '../buzlime_integration/integration_entry.dart';
import '../core/app_colors.dart';
import '../core/sales_data.dart';
import '../core/i18n.dart';
import '../widgets/background_scaffold.dart';
import '../home_page.dart';
import 'sales_closed_page.dart';

// ═══════════════════════════════════════════════════════════════════════════════
class PreparingPage extends StatefulWidget {
  final String drinkCode; // 'LEMON' | 'ORANGE'
  final int sizeMl;       // 300 | 400
  final String volume;    // '300ml' | '400ml'
  final String price;     // '30' | '45'
  final int seconds;      // tahmini hazırlık süresi (fallback için)

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

// ─── TickerProviderStateMixin: 2 AnimationController için zorunlu ─────────────
class _PreparingPageState extends State<PreparingPage>
    with TickerProviderStateMixin {

  // ── Bağlantı ────────────────────────────────────────────────────────────────
  StreamSubscription? _stepSub;
  StreamSubscription? _telSub;
  bool _finished = false;

  // ── Progress durumu (setState'siz; AnimatedBuilder ile render) ───────────────
  double _arduinoProgress = 0.0; // Arduino'dan gelen en yüksek değer
  double _targetProgress  = 0.0; // Animasyonun hedefi (geri gitmez)

  // ── UI durumu (setState gerektirir) ─────────────────────────────────────────
  bool _arduinoSynced = false; // Arduino veri gönderdi mi?
  bool _pickupMode    = false; // Teslim kapısı açıldı mı?
  String _mcuState    = '';    // Arduino'dan gelen son state string'i

  // ── AnimationController 1: ilerleme çubuğu ──────────────────────────────────
  // .animateTo() ile setState olmadan smooth güncelleme yapılır.
  // AnimatedBuilder bu controller'ı dinler → otomatik rebuild.
  late final AnimationController _barCtrl;

  // ── AnimationController 2: ikon nabzı ───────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  // ── Fallback timer: Arduino yoksa yavaş ilerleme ─────────────────────────────
  Timer? _fallbackTimer;
  Timer? _hardTimeout;
  int    _fallbackElapsedMs = 0;
  late final int _totalMs;

  // ─────────────────────────────────────────────────────────────────────────────
  String get _drinkTitle => widget.drinkCode == 'LEMON'
      ? trEn('Limon', 'Lemon')
      : trEn('Portakal', 'Orange');

  String get _statusLabel {
    if (_pickupMode) return trEn('Ürününüzü alın', 'Take your product');
    final up = _mcuState.toUpperCase();
    if (up.contains('CUP') || up.contains('DISPENSE'))
      return trEn('Bardak hazırlanıyor', 'Preparing cup');
    if (up.contains('PUMP') || up.contains('FILL'))
      return trEn('Dolum yapılıyor', 'Filling drink');
    if (up.contains('VALVE'))
      return trEn('Vana açılıyor', 'Opening valve');
    if (up.contains('PREPARING') || up.contains('WAIT'))
      return trEn('Ürününüz hazırlanıyor', 'Preparing your product');
    return trEn('Ürününüz hazırlanıyor', 'Preparing your product');
  }

  // ═════════════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _totalMs = (widget.seconds * 1000).clamp(5000, 120000);

    // ── AnimationController: ilerleme çubuğu ──────────────────────────────────
    _barCtrl = AnimationController(
      vsync: this,
      value: 0.0,
      lowerBound: 0.0,
      upperBound: 1.0,
      // duration kullanmıyoruz; animateTo() her seferinde kendi duration'ını alır
      duration: const Duration(milliseconds: 1),
    );

    // ── AnimationController: nabız ────────────────────────────────────────────
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.93, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // ── Fallback timer ─────────────────────────────────────────────────────────
    // Arduino sessizse her 300ms'de yavaşça ilerliyoruz (max %90)
    _fallbackTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (_finished) return;
      _fallbackElapsedMs += 300;
      if (_fallbackElapsedMs > _totalMs) _fallbackElapsedMs = _totalMs;
      final fp = (_fallbackElapsedMs / _totalMs).clamp(0.0, 0.90);
      // Sadece Arduino'nun gerisindeyse fallback ilerler
      _animateTo(fp);
    });

    // ── Hard timeout ──────────────────────────────────────────────────────────
    final hardSec = (widget.seconds + 45).clamp(60, 300);
    _hardTimeout = Timer(Duration(seconds: hardSec), () {
      if (!_finished && mounted) _goSalesClosed();
    });

    // ── Arduino bağlantısı ────────────────────────────────────────────────────
    _startOrderFlow();
  }

  // ── Smooth progress animasyonu (setState YOK → build güvenli) ────────────────
  void _animateTo(double target) {
    final clamped = target.clamp(0.0, 1.0);
    if (clamped <= _targetProgress) return; // asla geri gitme
    _targetProgress = clamped;
    // AnimationController.animateTo → AnimatedBuilder rebuild tetikler
    _barCtrl.animateTo(
      clamped,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
    );
  }

  // ── Arduino bağlantı akışı ────────────────────────────────────────────────────
  Future<void> _startOrderFlow() async {
    try {
      final ctrl = getDeviceController();

      // Zaten bağlıysa (PaymentPage'den geldi) tekrar connect() çağırma
      if (!ctrl.isConnected) {
        final ok = await ctrl.connect();
        if (!ok) {
          if (mounted) _goSalesClosed();
          return;
        }
      }

      // ── PrepStep stream ────────────────────────────────────────────────────
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

      // ── Telemetry stream: Arduino'dan gelen gerçek progress ────────────────
      _telSub = ctrl.telemetryStream.stream.listen((t) {
        if (_finished || !mounted) return;

        // Bağlantı kesildi
        if (t.state == 'DISCONNECTED') { _goSalesClosed(); return; }

        // State string'i
        final stRaw = (t.state ?? '').trim();
        if (stRaw.isNotEmpty) {
          final up = stRaw.toUpperCase();

          // Pickup modu tespiti
          if ((up.contains('DELIVERY_OPEN') || up.contains('WAIT_PICKUP'))
              && !_pickupMode) {
            _fallbackTimer?.cancel();
            _hardTimeout?.cancel();
            _animateTo(1.0);
            setState(() => _pickupMode = true);
            return;
          }

          if (up != _mcuState) setState(() => _mcuState = up);
        }

        // ── Arduino progress → her zaman öncelikli ─────────────────────────
        final p = t.progress;
        if (p != null) {
          final v = p.clamp(0.0, 1.0);
          if (v > _arduinoProgress) {
            _arduinoProgress = v;
            // İlk Arduino verisi geldi → rozeti güncelle
            if (!_arduinoSynced) setState(() => _arduinoSynced = true);
            _animateTo(v); // fallback'in önündeyse geçersiz kılar
          }
        }
      });

    } catch (_) {
      if (mounted && !_finished) _goSalesClosed();
    }
  }

  // ── Hata / timeout → SalesClosedPage ──────────────────────────────────────────
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

  // ── ORDER_DONE → satış kaydet → HomePage ──────────────────────────────────────
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
    _barCtrl.dispose();    // AnimationController mutlaka dispose edilmeli
    _pulseCtrl.dispose();  // AnimationController mutlaka dispose edilmeli
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;

    return BackgroundScaffold(
      extendBodyBehindAppBar: true,
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(height: h * 0.04),

            // ── Ürün ikonu ───────────────────────────────────────────────────
            ScaleTransition(
              scale: _pickupMode
                  ? const AlwaysStoppedAnimation(1.0)
                  : _pulseAnim,
              child: _ProductImage(height: h * 0.26),
            ),

            SizedBox(height: h * 0.025),

            // ── Durum yazısı ─────────────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.12),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                _statusLabel,
                key: ValueKey(_statusLabel),
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

            // ── İçecek ve boyut ──────────────────────────────────────────────
            Text(
              '$_drinkTitle  •  ${widget.volume}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: (w * 0.026).clamp(15.0, 22.0),
                fontWeight: FontWeight.w500,
              ),
            ),

            const Spacer(),

            // ── İlerleme / Pickup bölgesi ────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.07),
              child: AnimatedCrossFade(
                duration: const Duration(milliseconds: 400),
                crossFadeState: _pickupMode
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: _ProgressSection(
                  barCtrl: _barCtrl,
                  arduinoSynced: _arduinoSynced,
                ),
                secondChild: const _PickupBanner(),
              ),
            ),

            SizedBox(height: h * 0.07),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Ürün görseli — asset yoksa ikon gösterir (crash yok)
// ═══════════════════════════════════════════════════════════════════════════════
class _ProductImage extends StatelessWidget {
  final double height;
  const _ProductImage({required this.height});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/buttons_new/product.png',
      height: height,
      fit: BoxFit.contain,
      // Asset yoksa kırmızı ekran yerine ikon göster
      errorBuilder: (_, __, ___) => Icon(
        Icons.local_drink_rounded,
        size: height * 0.6,
        color: Colors.white.withOpacity(0.8),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Progress bölgesi — ayrı widget, gereksiz rebuild'i önler
// AnimationController dinlenir → setState gerekmiyor
// ═══════════════════════════════════════════════════════════════════════════════
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
      builder: (context, _) {
        final val = barCtrl.value;
        final pct = (val * 100).toInt().clamp(0, 100);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Yüzde + Arduino rozeti
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

            // İlerleme çubuğu
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: LinearProgressIndicator(
                value: val,
                minHeight: 20,
                valueColor: AlwaysStoppedAnimation<Color>(
                  arduinoSynced
                      ? AppColors.bzPrimary       // Arduino aktif → teal
                      : const Color(0xFF026B55),  // Fallback → koyu yeşil
                ),
                backgroundColor:
                const Color(0xFF4EF2C0).withOpacity(0.30),
              ),
            ),

            const SizedBox(height: 16),

            // Adım göstergesi
            _StepRow(progress: val),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Arduino senkron rozeti
// ═══════════════════════════════════════════════════════════════════════════════
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

// ═══════════════════════════════════════════════════════════════════════════════
// Pickup banner
// ═══════════════════════════════════════════════════════════════════════════════
class _PickupBanner extends StatelessWidget {
  const _PickupBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.bzPrimary.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border:
        Border.all(color: AppColors.bzPrimary.withOpacity(0.55), width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 34),
          const SizedBox(width: 14),
          Text(
            trEn('Teslim kapağı açık', 'Delivery door open'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Adım göstergesi — progress değerini parametre olarak alır (setState yok)
// ═══════════════════════════════════════════════════════════════════════════════
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
                width: 44,
                height: 44,
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
                child: Icon(
                  s.icon,
                  color: done ? Colors.white : active ? Colors.white70 : Colors.white30,
                  size: 20,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                trEn(s.tr, s.en),
                style: TextStyle(
                  color: done
                      ? Colors.white
                      : active
                      ? Colors.white60
                      : Colors.white.withOpacity(0.30),
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
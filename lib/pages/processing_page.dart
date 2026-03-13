// processing_page.dart — Revize Edildi
// 90 dakika kronometresi (admin panel içecek doldurma sonrası)
// Navigasyon: süre bitince veya processing.isActive=false → HomePage
import 'package:buzi_kiosk/widgets/admin_keypad_dialog.dart';
import 'package:buzi_kiosk/pages/sales_closed_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_info.dart';
import '../core/i18n.dart';
import '../home_page.dart';
import 'dart:async';

class ProcessingPage extends StatefulWidget {
  const ProcessingPage({super.key});

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<ProcessingPage>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  StreamSubscription<DocumentSnapshot>? _listener;
  StreamSubscription<DocumentSnapshot>? _statusListener;
  Duration _remaining = Duration.zero;
  Duration _total = const Duration(minutes: 90);
  bool _navigated = false;
  bool _adminDialogOpen = false;

  // Nabız animasyonu (süre ikonu için)
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.9, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _startCountdown();
    _listenProcessingChanges();
    _listenStatusChanges();
  }

  void _listenProcessingChanges() {
    _listener = FirebaseFirestore.instance
        .collection('machines')
        .doc(kMachineId)
        .snapshots()
        .listen((snapshot) {
      if (_adminDialogOpen) return;
      if (!snapshot.exists) return;
      final data = snapshot.data();
      final processing = data?['processing'] as Map<String, dynamic>?;
      final isActive = processing?['isActive'] == true;
      if (!isActive && !_navigated && mounted) {
        _navigated = true;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    });
  }

  void _listenStatusChanges() {
    _statusListener = FirebaseFirestore.instance
        .collection('machines')
        .doc(kMachineId)
        .snapshots()
        .listen((snapshot) {
      if (_adminDialogOpen) return;
      final data = snapshot.data();
      final isActive = data?['status']?['isActive'] ?? true;
      if (!isActive && mounted && !_navigated) {
        _navigated = true;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SalesClosedPage()),
        );
      }
    });
  }

  Future<void> _startCountdown() async {
    final docRef = FirebaseFirestore.instance
        .collection('machines')
        .doc(kMachineId);
    final docSnapshot = await docRef.get();
    if (!docSnapshot.exists) return;

    final data = docSnapshot.data();
    if (data == null ||
        !data.containsKey('processing') ||
        data['processing'] is! Map) return;

    final processing = data['processing'] as Map<String, dynamic>;
    if (!processing.containsKey('until')) return;

    final Timestamp untilTimestamp = processing['until'];
    final until = untilTimestamp.toDate();

    // Toplam süreyi hesapla (90 dk olması lazım, ama Firestore'dan al)
    final start = until.subtract(const Duration(minutes: 90));
    final totalDiff = until.difference(start);
    if (totalDiff.inSeconds > 0) {
      setState(() => _total = totalDiff);
    }

    _updateRemaining(until);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining(until);
    });
  }

  void _updateRemaining(DateTime until) {
    final now = DateTime.now();
    final diff = until.difference(now);
    if (diff.isNegative || diff == Duration.zero) {
      _timer?.cancel();
      FirebaseFirestore.instance
          .collection('machines')
          .doc(kMachineId)
          .update({'processing.isActive': false});
    } else {
      setState(() => _remaining = diff);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _listener?.cancel();
    _statusListener?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  double get _progress {
    if (_total.inSeconds == 0) return 0;
    final elapsed = _total.inSeconds - _remaining.inSeconds;
    return (elapsed / _total.inSeconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(screenWidth * 0.18),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.bzPrimaryDark,
          leadingWidth: screenWidth * 0.1,
          leading: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: GestureDetector(
              onTap: () {
                toggleLanguage();
                setState(() {});
              },
              child: Transform.scale(
                scale: 2,
                child: Image.asset(
                  'assets/buttons_new/lang_change.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 4),
              child: GestureDetector(
                onTap: () {
                  setState(() => _adminDialogOpen = true);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const AdminKeypadDialog(),
                    ).then((_) {
                      if (mounted) setState(() => _adminDialogOpen = false);
                    });
                  });
                },
                child: const Text('⚙️', style: TextStyle(fontSize: 36)),
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Arka plan
          Positioned.fill(
            child: Image.asset(
              isTurkish
                  ? 'assets/wallpapers/timer_tr.jpg'
                  : 'assets/wallpapers/timer_en.jpg',
              key: ValueKey(isTurkish),
              fit: BoxFit.cover,
            ),
          ),

          // İlerleme çubuğu (alt kısım)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              color: AppColors.bzPrimary,
              backgroundColor: Colors.white.withOpacity(0.2),
            ),
          ),

          // Kronometre dairesi (orijinal konumda)
          Positioned(
            left: screenWidth * 0.4,
            top: screenHeight * 0.335,
            child: ScaleTransition(
              scale: _pulse,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bzPrimary, width: 5),
                  color: Colors.black.withOpacity(0.35),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.bzPrimary.withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 4,
                    )
                  ],
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _remaining == Duration.zero ? '--:--' : _fmt(_remaining),
                      style: const TextStyle(
                        fontSize: 58,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            blurRadius: 20,
                            color: Colors.black54,
                            offset: Offset(2, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isTurkish ? 'kalan' : 'remaining',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
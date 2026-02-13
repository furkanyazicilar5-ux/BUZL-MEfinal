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

class _ProcessingPageState extends State<ProcessingPage> {
  Timer? _timer;
  StreamSubscription<DocumentSnapshot>? _listener;
  StreamSubscription<DocumentSnapshot>? _statusListener;
  Duration _remaining = Duration.zero;
  bool _navigated = false;
  bool _adminDialogOpen = false;

  @override
  void initState() {
    super.initState();
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
    final docRef = FirebaseFirestore.instance.collection('machines').doc(kMachineId);
    final docSnapshot = await docRef.get();
    if (!docSnapshot.exists) return;

    final data = docSnapshot.data();
    if (data == null ||
        !data.containsKey('processing') ||
        data['processing'] is! Map) {
      return;
    }

    final processing = data['processing'] as Map<String, dynamic>;
    if (!processing.containsKey('until')) return;

    final Timestamp untilTimestamp = processing['until'];
    final until = untilTimestamp.toDate();
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
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
                child: const Text(
                  '⚙️',
                  style: TextStyle(fontSize: 36),
                ),
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              isTurkish
                  ? 'assets/wallpapers/timer_tr.jpg'
                  : 'assets/wallpapers/timer_en.jpg',
              key: ValueKey(isTurkish),
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            left: screenWidth * 0.4,
            top: screenHeight * 0.335,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 6),
                color: Colors.black26,
              ),
              alignment: Alignment.center,
              child: Text(
                _remaining == Duration.zero ? '' : _formatDuration(_remaining),
                style: const TextStyle(
                  fontSize: 64,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      blurRadius: 43,
                      color: Colors.black54,
                      offset: Offset(2, 2),
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

// sales_closed_page.dart — Revize Edildi
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/app_info.dart';
import '../core/app_colors.dart';
import '../core/i18n.dart';
import 'package:buzi_kiosk/widgets/admin_keypad_dialog.dart';
import '../home_page.dart';
import 'dart:async';

class SalesClosedPage extends StatefulWidget {
  const SalesClosedPage({super.key, this.autoReturnHome = true});
  final bool autoReturnHome;

  @override
  State<SalesClosedPage> createState() => _SalesClosedPageState();
}

class _SalesClosedPageState extends State<SalesClosedPage>
    with SingleTickerProviderStateMixin {
  StreamSubscription<DocumentSnapshot>? _sub;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    if (widget.autoReturnHome) {
      _sub = FirebaseFirestore.instance
          .collection('machines')
          .doc(kMachineId)
          .snapshots()
          .listen((snapshot) {
        final data = snapshot.data();
        final isActive = data?['status']?['isActive'] ?? true;
        if (isActive && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTR = isTurkish;
    final screenWidth = MediaQuery.of(context).size.width;

    return PopScope(
      canPop: false,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: AppColors.bzTealDeep,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(screenWidth * 0.18),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: AppColors.bzPrimaryDark,
            leadingWidth: screenWidth * 0.1,
            leading: GestureDetector(
              onTap: () {
                toggleLanguage();
                setState(() {});
              },
              child: Transform.scale(
                scale: 2,
                child: Image.asset('assets/buttons_new/lang_change.png'),
              ),
            ),
            centerTitle: true,
            title: Text(
              isTR ? 'Satış Kapalı' : 'Sales Closed',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
            actions: [
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => const AdminKeypadDialog(),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.only(right: 12, top: 4),
                  child: Text('⚙️', style: TextStyle(fontSize: 36)),
                ),
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            // Arka plan görseli
            Positioned.fill(
              child: Image.asset(
                isTR
                    ? 'assets/wallpapers/out_of_order_tr.png'
                    : 'assets/wallpapers/out_of_order_en.png',
                key: ValueKey(isTR),
                fit: BoxFit.cover,
              ),
            ),

            // Hata modu bilgi banner'ı
            if (!widget.autoReturnHome)
              Positioned(
                bottom: 40,
                left: 24,
                right: 24,
                child: ScaleTransition(
                  scale: _pulse,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.75),
                          Colors.black.withOpacity(0.55),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.15), width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.orange, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isTR
                                ? 'Teknik bir sorun oluştu.\nLütfen teknik servis ile iletişime geçin.'
                                : 'A technical issue occurred.\nPlease contact technical support.',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
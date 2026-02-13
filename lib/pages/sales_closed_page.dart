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

  /// Firestore'da satış tekrar açıldığında otomatik Home'a dönsün mü?
  /// Hata akışlarında (MCU/proses arızası) false gönderilir.
  final bool autoReturnHome;

  @override
  State<SalesClosedPage> createState() => _SalesClosedPageState();
}

class _SalesClosedPageState extends State<SalesClosedPage> {
  StreamSubscription<DocumentSnapshot>? _sub;

  @override
  void initState() {
    super.initState();

    // ★ Satış tekrar açıldığında HomePage’e geri dön (opsiyonel)
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
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            actions: [
              GestureDetector(
                onTap: () {
                  showDialog(context: context, builder: (_) => const AdminKeypadDialog());
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
            Positioned.fill(
              child: Image.asset(
                isTR
                    ? 'assets/wallpapers/out_of_order_tr.png'
                    : 'assets/wallpapers/out_of_order_en.png',
                key: ValueKey(isTR),
                fit: BoxFit.cover,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
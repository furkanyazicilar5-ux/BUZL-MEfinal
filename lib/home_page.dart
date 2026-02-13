import 'package:buzi_kiosk/widgets/admin_keypad_dialog.dart';
import 'package:buzi_kiosk/pages/sales_closed_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:buzi_kiosk/pages/drink_page.dart';
import 'package:buzi_kiosk/pages/processing_page.dart';
import 'package:flutter/material.dart';
import 'core/i18n.dart';
import 'core/app_info.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    WakelockPlus.enable();

  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleStartPressed() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('machines')
          .doc(kMachineId)
          .get();

      final data = doc.data();
      final isActive = data?['status']?['isActive'] ?? true;

      if (!mounted) return;

      if (!isActive) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SalesClosedPage()),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DrinkPage()),
        );
      }
    } catch (e) {
      debugPrint('Firestore hata: $e');
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SalesClosedPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final logoWidth = screenWidth * 0.45;
    final startButtonWidth = screenWidth * 0.20;
    final bottomPadding = screenHeight * 0.05;

    return PopScope(
      canPop: false,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(screenWidth * 0.18),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: Colors.white,
            leadingWidth: screenWidth * 0.1,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: GestureDetector(
                onTap: () {
                  toggleLanguage();
                  setState(() {});
                },
                child: Transform.scale(
                  scale: 1.8,
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
                    showDialog(
                      context: context,
                      builder: (_) => const AdminKeypadDialog(),
                    );
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
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('machines').doc(kMachineId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data?.data() as Map<String, dynamic>?;
            final isActive = data?['status']?['isActive'] ?? true;
            final processing = data?['processing'] as Map<String, dynamic>?;

            // PDF akışı: makine satışa kapalıysa Home yerine SalesClosed göster.
            if (!isActive) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const SalesClosedPage()),
                  );
                }
              });
              return const SizedBox.shrink();
            }

            if (processing?['isActive'] == true) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const ProcessingPage()),
                  );
                }
              });
              return const SizedBox.shrink();
            }
            // If not active, show home body as before
            return LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/wallpapers/wallpaper_empty.jpeg',
                      fit: BoxFit.cover,
                    ),
                    // Ortadaki logo (breathing efekt)
                    Center(
                      child: AnimatedBuilder(
                        animation: _animation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _animation.value,
                            child: child,
                          );
                        },
                        child: Image.asset(
                          'assets/wallpapers/logo_final.png',
                          width: logoWidth,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    // Alt ortadaki Başla butonu
                    Positioned(
                      bottom: bottomPadding,
                      left: (screenWidth - startButtonWidth) / 2,
                      child: GestureDetector(
                        onTap: _handleStartPressed,
                        child: Image.asset(
                          trEn('assets/buttons_new/start_tr.png', 'assets/buttons_new/start_en.png'),
                          width: startButtonWidth,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/background_scaffold.dart';
import 'package:flutter/material.dart';
import '../core/app_info.dart';
import '../core/i18n.dart';
import 'payment_page.dart';
import '../core/inactivity_watcher.dart';

class ProductPage extends StatelessWidget {
  final String drinkCode; // 'LEMON' | 'ORANGE'
  const ProductPage({super.key, required this.drinkCode});

  Future<Map<String, dynamic>?> _fetchMachineData() async {
    final snap = await FirebaseFirestore.instance
        .collection('machines')
        .doc(kMachineId)
        .get();
    return snap.data();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchMachineData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }

        final machine = snapshot.data!;
        final inv = Map<String, dynamic>.from(machine['inventory'] ?? {});
        final int smallCups = (inv['smallCups'] ?? 0);
        final int largeCups = (inv['largeCups'] ?? 0);

        final bool canSellSmall = smallCups > 3;
        final bool canSellLarge = largeCups > 3;

        return InactivityWrapper(
          timeout: TimeoutDurations.short,
          onTimeout: () {
            if (context.mounted) {
              Navigator.pushReplacementNamed(context, '/home');
            }
          },
          child: BackgroundScaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              title: Text(
                trEn('Ürün Seçimi', 'Product Selection'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: true,
              iconTheme: const IconThemeData(color: Colors.white),
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // küçük
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Opacity(
                      opacity: canSellSmall ? 1.0 : 0.4,
                      child: InkWell(
                        onTap: canSellSmall
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PaymentPage(
                                      drinkCode: drinkCode,
                                      sizeMl: 300,
                                      volume: '300ml',
                                      price: '30',
                                      seconds: 10,
                                    ),
                                  ),
                                );
                              }
                            : null,
                        child: SizedBox(
                          width: 405,
                          height: 200,
                          child: ColorFiltered(
                            colorFilter: canSellSmall
                                ? const ColorFilter.mode(
                                    Colors.transparent, BlendMode.multiply)
                                : const ColorFilter.mode(
                                    Colors.grey, BlendMode.saturation),
                            child: Image.asset(
                              isTurkish
                                  ? 'assets/buttons_new/small_tr.png'
                                  : 'assets/buttons_new/small_en.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Text(
                      '30₺',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold),
                    ),
                    if (!canSellSmall)
                      const Text('Stokta yok',
                          style: TextStyle(
                              fontSize: 30,
                              color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
                // büyük
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Opacity(
                      opacity: canSellLarge ? 1.0 : 0.4,
                      child: InkWell(
                        onTap: canSellLarge
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PaymentPage(
                                      drinkCode: drinkCode,
                                      sizeMl: 400,
                                      volume: '400ml',
                                      price: '45',
                                      seconds: 15,
                                    ),
                                  ),
                                );
                              }
                            : null,
                        child: SizedBox(
                          width: 380,
                          height: 240,
                          child: ColorFiltered(
                            colorFilter: canSellLarge
                                ? const ColorFilter.mode(
                                    Colors.transparent, BlendMode.multiply)
                                : const ColorFilter.mode(
                                    Colors.grey, BlendMode.saturation),
                            child: Image.asset(
                              isTurkish
                                  ? 'assets/buttons_new/large_tr.png'
                                  : 'assets/buttons_new/large_en.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '45₺',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold),
                    ),
                    if (!canSellLarge)
                      const Text('Stokta yok',
                          style: TextStyle(
                            fontSize: 30,
                              color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

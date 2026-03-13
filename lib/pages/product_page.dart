import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/background_scaffold.dart';
import 'package:flutter/material.dart';
import '../core/app_info.dart';
import '../core/app_colors.dart';
import '../core/i18n.dart';
import 'payment_page.dart';
import '../core/inactivity_watcher.dart';

/// ProductPage — Revize Edildi
///
/// Fiyatlar artık Firestore'dan çekiliyor:
///   machines/{id}/pricing.small  (₺ cinsinden int/double)
///   machines/{id}/pricing.large
/// Firestore'da yoksa varsayılan: küçük 30₺, büyük 45₺
class ProductPage extends StatelessWidget {
  final String drinkCode;
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
            backgroundColor: Color(0xFF00332C),
            body: Center(
                child: CircularProgressIndicator(color: Colors.white)),
          );
        }

        final machine = snapshot.data!;
        final inv = Map<String, dynamic>.from(machine['inventory'] ?? {});
        final pricing =
        Map<String, dynamic>.from(machine['pricing'] ?? {});

        final int smallCups = (inv['smallCups'] ?? 0);
        final int largeCups = (inv['largeCups'] ?? 0);
        final bool canSellSmall = smallCups > 3;
        final bool canSellLarge = largeCups > 3;

        // Fiyatlar Firestore'dan, yoksa varsayılan
        final double smallPrice =
            (pricing['small'] as num?)?.toDouble() ?? 30.0;
        final double largePrice =
            (pricing['large'] as num?)?.toDouble() ?? 45.0;

        final drinkName = drinkCode == 'LEMON'
            ? trEn('Limon', 'Lemon')
            : trEn('Portakal', 'Orange');

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
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 26),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                trEn('Boy Seçimi', 'Size Selection'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              centerTitle: true,
            ),
            child: Column(
              children: [
                // Üst boşluk (AppBar altı)
                const SizedBox(height: 100),

                // İçecek adı etiketi
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.3), width: 1.5),
                  ),
                  child: Text(
                    '🥤 $drinkName',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600),
                  ),
                ),

                const Spacer(),

                // Boyut kartları
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _SizeCard(
                        labelTr: 'Küçük',
                        labelEn: 'Small',
                        volume: '300ml',
                        sizeMl: 300,
                        priceStr: '${smallPrice.toStringAsFixed(0)}₺',
                        priceDouble: smallPrice,
                        drinkCode: drinkCode,
                        available: canSellSmall,
                        seconds: 90,
                        isLarge: false,
                        imageAssetTr: 'assets/buttons_new/small_tr.png',
                        imageAssetEn: 'assets/buttons_new/small_en.png',
                      ),
                      _SizeCard(
                        labelTr: 'Büyük',
                        labelEn: 'Large',
                        volume: '400ml',
                        sizeMl: 400,
                        priceStr: '${largePrice.toStringAsFixed(0)}₺',
                        priceDouble: largePrice,
                        drinkCode: drinkCode,
                        available: canSellLarge,
                        seconds: 120,
                        isLarge: true,
                        imageAssetTr: 'assets/buttons_new/large_tr.png',
                        imageAssetEn: 'assets/buttons_new/large_en.png',
                      ),
                    ],
                  ),
                ),

                const Spacer(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SizeCard extends StatelessWidget {
  final String labelTr, labelEn;
  final String volume;
  final int sizeMl;
  final String priceStr;
  final double priceDouble;
  final String drinkCode;
  final bool available;
  final int seconds;
  final bool isLarge;
  final String imageAssetTr, imageAssetEn;

  const _SizeCard({
    required this.labelTr,
    required this.labelEn,
    required this.volume,
    required this.sizeMl,
    required this.priceStr,
    required this.priceDouble,
    required this.drinkCode,
    required this.available,
    required this.seconds,
    required this.isLarge,
    required this.imageAssetTr,
    required this.imageAssetEn,
  });

  @override
  Widget build(BuildContext context) {
    final imageW = isLarge ? 340.0 : 280.0;
    final imageH = isLarge ? 220.0 : 170.0;

    return GestureDetector(
      onTap: available
          ? () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentPage(
              drinkCode: drinkCode,
              sizeMl: sizeMl,
              volume: volume,
              price: priceDouble.toStringAsFixed(0),
              seconds: seconds,
            ),
          ),
        );
      }
          : null,
      child: AnimatedOpacity(
        opacity: available ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kart çerçevesi
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: available
                      ? Colors.white.withOpacity(0.4)
                      : Colors.white.withOpacity(0.1),
                  width: 2,
                ),
                color: available
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.15),
                boxShadow: available
                    ? [
                  BoxShadow(
                    color: AppColors.bzPrimary.withOpacity(0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                ]
                    : [],
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                children: [
                  ColorFiltered(
                    colorFilter: available
                        ? const ColorFilter.mode(
                        Colors.transparent, BlendMode.multiply)
                        : const ColorFilter.mode(
                        Colors.grey, BlendMode.saturation),
                    child: Image.asset(
                      isTurkish ? imageAssetTr : imageAssetEn,
                      width: imageW,
                      height: imageH,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    trEn(labelTr, labelEn),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    volume,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Fiyat etiketi
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: available
                    ? AppColors.bzPrimary
                    : Colors.grey.withOpacity(0.4),
                borderRadius: BorderRadius.circular(30),
                boxShadow: available
                    ? [
                  BoxShadow(
                    color: AppColors.bzPrimary.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
                    : [],
              ),
              child: Text(
                available ? priceStr : trEn('Stokta Yok', 'Out of Stock'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
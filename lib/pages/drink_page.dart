import 'package:flutter/material.dart';

import '../core/inactivity_watcher.dart';
import '../core/i18n.dart';
import '../widgets/background_scaffold.dart';
import 'product_page.dart';

class DrinkPage extends StatelessWidget {
  const DrinkPage({super.key});

  void _go(BuildContext context, String drinkCode) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductPage(drinkCode: drinkCode)),
    );
  }

  Widget _drinkCard({
    required BuildContext context,
    required String labelTr,
    required String labelEn,
    required String drinkCode,
    required double cardW,
    required double cardH,
    required double fontSize,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _go(context, drinkCode),
      child: SizedBox(
        width: cardW,
        height: cardH,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Buton zemini
            Positioned.fill(
              child: Image.asset(
                'assets/buttons_new/product.png',
                fit: BoxFit.contain,
              ),
            ),

            // Yazı: taşma olmasın diye FittedBox
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  trEn(labelTr, labelEn),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    shadows: const [
                      Shadow(blurRadius: 10, offset: Offset(0, 2)),
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

  @override
  Widget build(BuildContext context) {
    return InactivityWrapper(
      timeout: TimeoutDurations.short,
      onTimeout: () {
        if (context.mounted) Navigator.pushReplacementNamed(context, '/home');
      },
      child: BackgroundScaffold(
        // Mockup hissi için AppBar kullanma
        extendBodyBehindAppBar: true,
        appBar: null,

        // İçerik
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;

            // Kiosk ekranında büyük kart hedefi:
            // genişliğin yaklaşık %35'i kadar kart, yükseklik oranlı
            final cardW = w * 0.36;
            final cardH = cardW * 0.52; // buton görsel oranına yakın
            final gap = w * 0.06;

            final titleSize = (w * 0.045).clamp(44.0, 72.0);
            final cardFont = (w * 0.040).clamp(34.0, 60.0);

            return Stack(
              children: [
                // Başlık (AppBar değil, tasarımın parçası)
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: h * 0.06),
                    child: Text(
                      trEn('İçecek Seçimi', 'Drink Selection'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        shadows: const [
                          Shadow(blurRadius: 12, offset: Offset(0, 2)),
                        ],
                      ),
                    ),
                  ),
                ),

                // Orta alan: 2 büyük kart
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _drinkCard(
                        context: context,
                        labelTr: 'Limon',
                        labelEn: 'Lemon',
                        drinkCode: 'LEMON',
                        cardW: cardW,
                        cardH: cardH,
                        fontSize: cardFont,
                      ),
                      SizedBox(width: gap),
                      _drinkCard(
                        context: context,
                        labelTr: 'Portakal',
                        labelEn: 'Orange',
                        drinkCode: 'ORANGE',
                        cardW: cardW,
                        cardH: cardH,
                        fontSize: cardFont,
                      ),
                    ],
                  ),
                ),

                // Geri butonu (mockup'ta sol üst ok var ya)
                Positioned(
                  left: 16,
                  top: 16,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 34),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

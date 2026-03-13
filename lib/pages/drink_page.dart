// ══════════════════════════════════════════════════════════════
// drink_page.dart — Revize Edildi
// ══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import '../core/inactivity_watcher.dart';
import '../core/i18n.dart';
import '../core/app_colors.dart';
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

  @override
  Widget build(BuildContext context) {
    return InactivityWrapper(
      timeout: TimeoutDurations.short,
      onTimeout: () {
        if (context.mounted) Navigator.pushReplacementNamed(context, '/home');
      },
      child: BackgroundScaffold(
        extendBodyBehindAppBar: true,
        appBar: null,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;
            final cardW = w * 0.36;
            final cardH = cardW * 0.52;
            final gap = w * 0.06;
            final titleSize = (w * 0.045).clamp(40.0, 68.0);
            final cardFont = (w * 0.038).clamp(30.0, 56.0);

            return Stack(
              children: [
                // Başlık
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: h * 0.07),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          trEn('İçecek Seçimi', 'Drink Selection'),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            shadows: const [
                              Shadow(blurRadius: 16, offset: Offset(0, 3)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          trEn(
                            'Taze sıkılmış meyve suyu seçin',
                            'Choose freshly squeezed juice',
                          ),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: (w * 0.02).clamp(16.0, 26.0),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Kartlar
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DrinkCard(
                        labelTr: 'Limon',
                        labelEn: 'Lemon',
                        emoji: '🍋',
                        drinkCode: 'LEMON',
                        cardW: cardW,
                        cardH: cardH,
                        fontSize: cardFont,
                        accentColor: const Color(0xFFF9C74F),
                        onTap: () => _go(context, 'LEMON'),
                      ),
                      SizedBox(width: gap),
                      _DrinkCard(
                        labelTr: 'Portakal',
                        labelEn: 'Orange',
                        emoji: '🍊',
                        drinkCode: 'ORANGE',
                        cardW: cardW,
                        cardH: cardH,
                        fontSize: cardFont,
                        accentColor: Colors.orange,
                        onTap: () => _go(context, 'ORANGE'),
                      ),
                    ],
                  ),
                ),

                // Geri butonu
                Positioned(
                  left: 16,
                  top: 16,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 30),
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

class _DrinkCard extends StatefulWidget {
  final String labelTr, labelEn, emoji, drinkCode;
  final double cardW, cardH, fontSize;
  final Color accentColor;
  final VoidCallback onTap;

  const _DrinkCard({
    required this.labelTr,
    required this.labelEn,
    required this.emoji,
    required this.drinkCode,
    required this.cardW,
    required this.cardH,
    required this.fontSize,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_DrinkCard> createState() => _DrinkCardState();
}

class _DrinkCardState extends State<_DrinkCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kart
            Container(
              width: widget.cardW,
              height: widget.cardH * 1.4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: widget.accentColor.withOpacity(0.5), width: 2),
                color: Colors.white.withOpacity(0.08),
                boxShadow: [
                  BoxShadow(
                    color: widget.accentColor.withOpacity(0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.emoji,
                    style: TextStyle(
                        fontSize: (widget.cardW * 0.22).clamp(48.0, 90.0)),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Image.asset(
                      'assets/buttons_new/product.png',
                      height: widget.cardH * 0.55,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Etiket
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              decoration: BoxDecoration(
                color: widget.accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                    color: widget.accentColor.withOpacity(0.4), width: 1.5),
              ),
              child: Text(
                trEn(widget.labelTr, widget.labelEn),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.fontSize * 0.7,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
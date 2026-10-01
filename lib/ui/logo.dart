// The WealthBuddy mark: steps rising to a gold coin. Same geometry as tool/make_brand.py,
// drawn as vectors so it stays sharp at any size.
import 'package:flutter/material.dart';

const brandTeal = Color(0xFF0F5C4D);
const brandGold = Color(0xFFD8AD5E);

class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 28, this.tile = true, this.tileColor = brandTeal});
  final double size;
  final bool tile; // draw on a rounded teal tile (app bar), or bare (on the teal splash)
  final Color tileColor;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MarkPainter(tile ? tileColor : null)),
      );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.tile);
  final Color? tile;
  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 100;
    if (tile != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(24 * k)), Paint()..color = tile!);
    }
    final path = Path()
      ..moveTo(22 * k, 74 * k)
      ..lineTo(40 * k, 74 * k)
      ..lineTo(40 * k, 58 * k)
      ..lineTo(58 * k, 58 * k)
      ..lineTo(58 * k, 42 * k)
      ..lineTo(72 * k, 42 * k);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8 * k
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(Offset(72 * k, 27 * k), 9 * k, Paint()..color = brandGold);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.tile != tile;
}

/// Logo plus "WealthBuddy" wordmark, for the app bar.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});
  @override
  Widget build(BuildContext context) => const Row(mainAxisSize: MainAxisSize.min, children: [
        LogoMark(size: 28),
        SizedBox(width: 10),
        Text.rich(TextSpan(children: [
          TextSpan(text: 'Wealth', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: 'Buddy', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFA8792A))),
        ])),
      ]);
}

/// The in-app splash: shown for about a second while saved data loads.
class SplashView extends StatelessWidget {
  const SplashView({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: brandTeal,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            LogoMark(size: 96, tile: false),
            SizedBox(height: 16),
            Text.rich(TextSpan(style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white), children: [
              TextSpan(text: 'Wealth'),
              TextSpan(text: 'Buddy', style: TextStyle(color: brandGold)),
            ])),
            SizedBox(height: 6),
            Text('Plan it. Afford it.', style: TextStyle(fontSize: 14, color: Color(0xFF9FE1CB))),
          ]),
        ),
      );
}

import 'package:flutter/material.dart';

/// Logo + nome em linha — use no lugar do texto 'APOSTINHA' em todas as AppBars
class AppBarBrand extends StatelessWidget {
  final double logoSize;
  final double fontSize;

  const AppBarBrand({super.key, this.logoSize = 28, this.fontSize = 18});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        const SizedBox(width: 8),
        Text(
          'APPostinha',
          style: TextStyle(
            color: const Color(0xFF00C851),
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    final paintOuter = Paint()
      ..color = const Color(0xFF00C851).withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final paintRing = Paint()
      ..color = const Color(0xFF00C851).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06;

    final paintInner = Paint()
      ..color = const Color(0xFF00C851)
      ..style = PaintingStyle.fill;

    // círculo externo (fundo)
    canvas.drawCircle(Offset(cx, cy), r, paintOuter);

    // anel
    canvas.drawCircle(Offset(cx, cy), r * 0.72, paintRing);

    // ponto central
    canvas.drawCircle(Offset(cx, cy), r * 0.28, paintInner);

    // linha diagonal (como um palpite/seta)
    final paintLine = Paint()
      ..color = const Color(0xFF00C851)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(cx + r * 0.38, cy - r * 0.62),
      Offset(cx + r * 0.72, cy - r * 0.92),
      paintLine,
    );

    // ponta da seta
    canvas.drawLine(
      Offset(cx + r * 0.72, cy - r * 0.92),
      Offset(cx + r * 0.46, cy - r * 0.92),
      paintLine,
    );
    canvas.drawLine(
      Offset(cx + r * 0.72, cy - r * 0.92),
      Offset(cx + r * 0.72, cy - r * 0.66),
      paintLine,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

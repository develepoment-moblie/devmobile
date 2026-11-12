import 'package:flutter/material.dart';

// Tracés géométriques des icônes à trait du prototype Figma.
enum NovaSymbol {
  home,
  calendar,
  bed,
  service,
  person,
  bell,
  spark,
  plus,
  chevron,
  check,
  box,
}

class NovaIcon extends StatelessWidget {
  final NovaSymbol symbol;
  final Color? color;
  final double size;
  const NovaIcon(this.symbol, {super.key, this.color, this.size = 20});
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _IconPainter(
        symbol,
        color ?? IconTheme.of(context).color ?? Colors.black,
      ),
    ),
  );
}

class _IconPainter extends CustomPainter {
  final NovaSymbol symbol;
  final Color color;
  _IconPainter(this.symbol, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void path(List<Offset> points, {bool close = false}) {
      final shape = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        shape.lineTo(point.dx, point.dy);
      }
      if (close) shape.close();
      canvas.drawPath(shape, p);
    }

    switch (symbol) {
      case NovaSymbol.home:
        path([const Offset(3, 11), const Offset(12, 3), const Offset(21, 11)]);
        path([
          const Offset(5, 10),
          const Offset(5, 20),
          const Offset(19, 20),
          const Offset(19, 10),
        ]);
        path([
          const Offset(9, 20),
          const Offset(9, 14),
          const Offset(15, 14),
          const Offset(15, 20),
        ]);
      case NovaSymbol.calendar:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 5, 18, 16),
            const Radius.circular(3),
          ),
          p,
        );
        path([const Offset(8, 3), const Offset(8, 7)]);
        path([const Offset(16, 3), const Offset(16, 7)]);
        path([const Offset(3, 10), const Offset(21, 10)]);
      case NovaSymbol.bed:
        path([
          const Offset(3, 19),
          const Offset(3, 11),
          const Offset(21, 11),
          const Offset(21, 19),
        ]);
        path([const Offset(3, 16), const Offset(21, 16)]);
        canvas.drawPath(
          Path()
            ..moveTo(6, 11)
            ..lineTo(6, 7)
            ..lineTo(11, 7)
            ..quadraticBezierTo(14, 7, 14, 10)
            ..lineTo(14, 11),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(14, 11)
            ..lineTo(14, 9)
            ..lineTo(18, 9)
            ..quadraticBezierTo(21, 9, 21, 12),
          p,
        );
      case NovaSymbol.service:
        path([const Offset(4, 17), const Offset(20, 17)]);
        canvas.drawPath(
          Path()
            ..moveTo(6, 17)
            ..cubicTo(6, 9, 18, 9, 18, 17),
          p,
        );
        path([const Offset(12, 8), const Offset(12, 11)]);
        canvas.drawCircle(const Offset(12, 6), 2, p);
      case NovaSymbol.person:
        canvas.drawCircle(const Offset(12, 8), 4, p);
        canvas.drawPath(
          Path()
            ..moveTo(4, 21)
            ..cubicTo(4, 10, 20, 10, 20, 21),
          p,
        );
      case NovaSymbol.bell:
        canvas.drawPath(
          Path()
            ..moveTo(18, 8)
            ..cubicTo(18, 0, 6, 0, 6, 8)
            ..cubicTo(6, 15, 3, 15, 3, 17)
            ..lineTo(21, 17)
            ..cubicTo(21, 15, 18, 15, 18, 8),
          p,
        );
        path([const Offset(10, 21), const Offset(14, 21)]);
      case NovaSymbol.spark:
        path([
          const Offset(12, 3),
          const Offset(10.5, 7.5),
          const Offset(6, 9),
          const Offset(10.5, 10.5),
          const Offset(12, 15),
          const Offset(13.5, 10.5),
          const Offset(18, 9),
          const Offset(13.5, 7.5),
        ], close: true);
      case NovaSymbol.plus:
        path([const Offset(12, 5), const Offset(12, 19)]);
        path([const Offset(5, 12), const Offset(19, 12)]);
      case NovaSymbol.chevron:
        path([const Offset(9, 18), const Offset(15, 12), const Offset(9, 6)]);
      case NovaSymbol.check:
        path([const Offset(5, 12), const Offset(10, 17), const Offset(20, 6)]);
      case NovaSymbol.box:
        path([
          const Offset(3, 7),
          const Offset(12, 3),
          const Offset(21, 7),
          const Offset(21, 18),
          const Offset(12, 22),
          const Offset(3, 18),
        ], close: true);
        path([const Offset(3, 7), const Offset(12, 11), const Offset(21, 7)]);
        path([const Offset(12, 11), const Offset(12, 22)]);
    }
  }

  @override
  bool shouldRepaint(_IconPainter oldDelegate) =>
      oldDelegate.symbol != symbol || oldDelegate.color != color;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

({Color top, Color ink}) _tableColors(String status) => switch (status) {
  'Réservée' => (top: const Color(0xFFDBEAFE), ink: const Color(0xFF1E40AF)),
  'Occupée' => (top: const Color(0xFFDDE2EA), ink: const Color(0xFF334155)),
  'Trop petite' => (top: const Color(0xFFF1F3F5), ink: const Color(0xFF526171)),
  'Sélectionnée' ||
  'Suggérée' => (top: const Color(0xFFFFE9A9), ink: const Color(0xFF754307)),
  _ => (top: const Color(0xFFCDEFD9), ink: const Color(0xFF176044)),
};

class DiningFloorGrid extends StatelessWidget {
  const DiningFloorGrid({
    super.key,
    required this.tables,
    required this.status,
    this.onTable,
    this.selected,
    this.suggested,
    this.suggestionRuns = 0,
  });

  final List<Map<String, Object?>> tables;
  final String Function(Map<String, Object?>) status;
  final void Function(Map<String, Object?>)? onTable;
  final int? selected;
  final int? suggested;
  final int suggestionRuns;

  @override
  Widget build(BuildContext context) {
    final byPosition = {
      for (final table in tables) table['position'] as int: table,
    };
    final labels = {for (final table in tables) status(table)};
    if (selected != null) labels.add('Sélectionnée');
    if (suggested != null) labels.add('Suggérée');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: Border.all(color: const Color(0xFFCCD6E0)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CustomPaint(
              painter: const _FloorTiles(),
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 9,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  mainAxisExtent: 92,
                ),
                itemBuilder: (context, index) {
                  final table = byPosition[index];
                  if (table == null) return const SizedBox.shrink();
                  final recommended = suggested == table['id'];
                  final label = status(table);
                  final displayed = recommended
                      ? 'Suggérée'
                      : selected == table['id']
                      ? 'Sélectionnée'
                      : label;
                  final palette = _tableColors(displayed);
                  final shape = table['shape'] as String;
                  final graphic = CustomPaint(
                    painter: _DiningTable(
                      table['seats'] as int,
                      shape,
                      palette.top,
                      palette.ink,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${table['name']}',
                            maxLines: 1,
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${table['seats']} places',
                            maxLines: 1,
                            style: TextStyle(color: palette.ink, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  );
                  return Tooltip(
                    message:
                        'Table ${table['name']} · ${table['seats']} places · $displayed',
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap:
                            onTable == null ||
                                label == 'Réservée' ||
                                label == 'Trop petite'
                            ? null
                            : () => onTable!(table),
                        child:
                            recommended &&
                                !MediaQuery.disableAnimationsOf(context)
                            ? TweenAnimationBuilder<double>(
                                key: ValueKey(suggestionRuns),
                                tween: Tween(begin: 0, end: 1),
                                duration: const Duration(milliseconds: 1500),
                                child: graphic,
                                builder: (context, progress, child) => Opacity(
                                  opacity:
                                      1 -
                                      0.38 *
                                          math.pow(
                                            math.sin(progress * math.pi * 3),
                                            2,
                                          ),
                                  child: child,
                                ),
                              )
                            : graphic,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (labels.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                for (final label in labels)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 9,
                        color: _tableColors(label).ink,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FloorTiles extends CustomPainter {
  const _FloorTiles();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = const Color(0xFFE9EEF3);
    for (var y = 0.0; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (var x = 0.0; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  @override
  bool shouldRepaint(_FloorTiles oldDelegate) => false;
}

class _DiningTable extends CustomPainter {
  const _DiningTable(this.seats, this.shape, this.color, this.accent);

  final int seats;
  final String shape;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final width = math.min(size.width - 14, shape == 'rectangle' ? 74.0 : 57.0);
    final height = shape == 'rectangle' ? 48.0 : width;
    if (width <= 0) return;
    final rect = Rect.fromCenter(center: center, width: width, height: height);
    final top = RRect.fromRectAndRadius(
      rect,
      Radius.circular(shape == 'circle' ? width / 2 : 8),
    );
    final chairPaint = Paint()..color = Color.lerp(color, accent, 0.46)!;
    if (shape == 'circle') {
      for (var chair = 0; chair < seats; chair++) {
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate((chair + 0.5) * math.pi * 2 / seats);
        _chair(canvas, Offset(0, -width / 2 - 3), chairPaint);
        canvas.restore();
      }
    } else {
      for (var chair = 0; chair < seats ~/ 2; chair++) {
        final x = rect.left + width * (chair + 1) / (seats ~/ 2 + 1);
        _chair(canvas, Offset(x, rect.top - 3), chairPaint);
        _chair(canvas, Offset(x, rect.bottom + 3), chairPaint);
      }
    }
    canvas.drawRRect(
      top.shift(const Offset(0, 3)),
      Paint()..color = accent.withValues(alpha: 0.15),
    );
    canvas.drawRRect(top, Paint()..color = color);
    canvas.drawRRect(
      top,
      Paint()
        ..color = accent.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  void _chair(Canvas canvas, Offset center, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 11, height: 9),
        const Radius.circular(2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_DiningTable oldDelegate) =>
      seats != oldDelegate.seats ||
      shape != oldDelegate.shape ||
      color != oldDelegate.color ||
      accent != oldDelegate.accent;
}

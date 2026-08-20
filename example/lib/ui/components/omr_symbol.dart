import 'package:flutter/material.dart';

/// The Omani Rial symbol, the same artwork the POS terminal draws on its
/// customer display, so an amount reads identically on both screens.
///
/// Mirrors `OmrSymbol.kt`. Drawn from the same path the Android drawable holds
/// rather than shipped as an image: it is one path, and a painter keeps the
/// example free of an SVG dependency and of asset-resolution variants.
///
/// Tinted rather than baked: the source path is a single dark shape, which
/// would vanish against a dark surface.
class OmrSymbol extends StatelessWidget {
  const OmrSymbol({super.key, this.tint, this.height = 18});

  /// Defaults to the surface's own foreground, as the Android version does.
  final Color? tint;

  /// 18dp in the Android drawable, whose viewport is 55 × 27.
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(height * _aspect, height),
      painter: _OmrPainter(
        tint ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  static const double _aspect = 55 / 27;
}

class _OmrPainter extends CustomPainter {
  const _OmrPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / _viewportWidth, size.height / _viewportHeight)
      ..drawPath(_path, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_OmrPainter oldDelegate) => oldDelegate.color != color;

  static const double _viewportWidth = 55;
  static const double _viewportHeight = 27;

  /// The `ic_omr_currency.xml` path, transcribed. The vector's own coordinates
  /// are kept so the two stay comparable if the artwork is ever revised.
  static final Path _path = Path()
    ..moveTo(17.627, 15.622)
    ..cubicTo(17.579, 11.823, 18.511, 8.255, 20.389, 4.986)
    ..cubicTo(23.171, 0.142, 26.225, -1.384, 31.516, 1.346)
    ..cubicTo(32.34, 1.77, 35.655, 4.081, 35.98, 4.785)
    ..cubicTo(36.368, 5.624, 33.858, 12.805, 33.732, 14.228)
    ..cubicTo(31.054, 11.332, 26.06, 6.61, 21.776, 8.852)
    ..cubicTo(18.298, 10.673, 20.848, 13.681, 22.661, 15.622)
    ..lineTo(54.268, 15.622)
    ..lineTo(52.229, 19.301)
    ..lineTo(26.556, 19.301)
    ..cubicTo(26.532, 19.44, 26.623, 19.555, 26.751, 19.656)
    ..cubicTo(27.712, 20.406, 33.003, 22.709, 34.067, 22.709)
    ..lineTo(50.336, 22.709)
    ..lineTo(48.26, 26.487)
    ..lineTo(0, 26.487)
    ..lineTo(2.078, 22.709)
    ..lineTo(21.642, 22.709)
    ..lineTo(18.776, 19.301)
    ..lineTo(3.967, 19.301)
    ..lineTo(6.006, 15.623)
    ..lineTo(17.627, 15.623)
    ..close();
}

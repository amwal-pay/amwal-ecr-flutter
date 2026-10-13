import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/painting.dart';

import 'receipt_layout.dart';

/// Thermal receipt PNG matching the simulator bilingual layout.
///
/// Width is fixed to [printerWidth] — the same 384 px used by merchant reprint
/// on the payment terminal.
abstract final class OperationReceiptImage {
  /// Max printable bitmap width on Amwal POS printers.
  static const int printerWidth = EcrPrintOutcome.printerWidth;

  static const int _pad = 14;
  static const double _line = 26;
  static const double _totalLine = 32;
  static const double _title = 30;
  static const double _subtitle = 17;
  static const double _meta = 17;
  static const double _emphasis = 26;
  static const double _total = 20;

  /// Builds a 384-wide PNG from an approved operation.
  static Future<Uint8List> png(
    EcrApproved result,
    EcrTransactionType type,
  ) =>
      pngFromLayout(ReceiptLayout.fromOperation(result, type));

  /// Renders [layout] as PNG bytes at [printerWidth].
  static Future<Uint8List> pngFromLayout(ReceiptLayout layout) async {
    final double height = _measureHeight(layout);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, printerWidth.toDouble(), height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    _draw(canvas, layout);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(printerWidth, height.round());
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) {
      throw StateError('Could not encode receipt PNG');
    }
    return bytes.buffer.asUint8List();
  }

  static double _measureHeight(ReceiptLayout layout) {
    double h = _pad.toDouble();
    h += _title + _line;
    h += _wrapLineCount(layout.tagline, _subtitle, printerWidth - _pad * 2) *
        _line;
    if (layout.mobileLine.isNotEmpty) h += _line;
    if (layout.crLine.isNotEmpty) h += _line;
    if (layout.taxLine.isNotEmpty) h += _line;
    h += 8 + _line + 14;
    h += _line * layout.meta.length;
    if (layout.orderType.isNotEmpty) h += 6 + _emphasis;
    if (layout.customerPhoneLabel.isNotEmpty) h += _line;
    h += 10 + _line;
    h += _line * layout.items.length;
    h += 10 + _line * layout.totals.length;
    h += 10 + _totalLine + 8;
    h += _line * 2 + _pad;
    return h < 200 ? 200 : h;
  }

  static void _draw(Canvas canvas, ReceiptLayout layout) {
    final TextPainter title = _painter(
      layout.businessName,
      size: _title,
      bold: true,
      align: TextAlign.center,
    );
    double y = _pad + _title;
    final double cx = printerWidth / 2;
    final double left = _pad.toDouble();
    final double right = (printerWidth - _pad).toDouble();
    final double maxW = right - left;

    title.paint(canvas, Offset(cx - title.width / 2, y - _title));
    y += _line;
    y = _drawWrapped(
      canvas,
      layout.tagline,
      size: _subtitle,
      left: left,
      startY: y,
      maxWidth: maxW,
      lineHeight: _line,
      center: true,
    );
    y += 6;

    for (final String line in <String>[
      layout.mobileLine,
      layout.crLine,
      layout.taxLine,
    ]) {
      if (line.isEmpty) continue;
      final TextPainter p = _painter(
        _ellipsize(line, _meta, maxW),
        size: _meta,
      );
      p.paint(canvas, Offset(left, y - _meta));
      y += _line;
    }
    y += 8;

    final TextPainter boxPaint = _painter(
      layout.orderBox,
      size: 17,
      bold: true,
      align: TextAlign.center,
    );
    const double boxPadX = 12;
    const double boxPadY = 10;
    final double boxW =
        (boxPaint.width + boxPadX * 2).clamp(0, maxW).toDouble();
    final double boxH = _line + boxPadY;
    final double boxLeft = cx - boxW / 2;
    final double boxTop = y - _line + 6;
    canvas.drawRect(
      Rect.fromLTWH(boxLeft, boxTop, boxW, boxH),
      Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    boxPaint.paint(canvas, Offset(cx - boxPaint.width / 2, y - 13));
    y += boxH + 14;

    for (final (String label, String value) in layout.meta) {
      _drawLabelValue(canvas, left, right, y, label, value, _meta);
      y += _line;
    }

    if (layout.orderType.isNotEmpty) {
      y += 6;
      final TextPainter emphasis = _painter(
        layout.orderType,
        size: _emphasis,
        bold: true,
        align: TextAlign.center,
      );
      emphasis.paint(canvas, Offset(cx - emphasis.width / 2, y - _emphasis));
      y += _emphasis;
    }
    if (layout.customerPhoneLabel.isNotEmpty) {
      final String phone = layout.customerPhone ?? '';
      final TextPainter p = _painter(
        _ellipsize('${layout.customerPhoneLabel}: $phone', _meta, maxW),
        size: _meta,
      );
      p.paint(canvas, Offset(left, y - _meta));
      y += _line;
    }

    y += 8;
    final Paint fillLine = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(left, y), Offset(right, y), fillLine);
    y += _line;
    _drawColumns(canvas, left, right, y, layout.itemsHeader, _meta);
    y += _line;
    for (final (String, String, String) row in layout.items) {
      _drawColumns(canvas, left, right, y, row, _meta);
      y += _line;
    }

    y += 6;
    canvas.drawLine(Offset(left, y), Offset(right, y), fillLine);
    y += _line;
    for (final (String label, String value) in layout.totals) {
      _drawLabelValue(canvas, left, right, y, label, value, _meta);
      y += _line;
    }
    y += 6;
    canvas.drawLine(Offset(left, y), Offset(right, y), fillLine);
    y += _totalLine;
    _drawLabelValue(
      canvas,
      left,
      right,
      y,
      layout.grandTotalLabel,
      layout.grandTotalValue,
      _total,
      bold: true,
    );
    y += _totalLine + 10;

    final TextPainter social = _painter(
      _ellipsize(layout.footerSocial, _subtitle, maxW),
      size: _subtitle,
      align: TextAlign.center,
    );
    social.paint(canvas, Offset(cx - social.width / 2, y - _subtitle));
    y += _line;
    final TextPainter thanks = _painter(
      layout.footerThanks,
      size: _subtitle,
      align: TextAlign.center,
    );
    thanks.paint(canvas, Offset(cx - thanks.width / 2, y - _subtitle));
  }

  static TextPainter _painter(
    String text, {
    required double size,
    bool bold = false,
    TextAlign align = TextAlign.left,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF000000),
          fontSize: size,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontFamily: 'sans-serif',
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout();
    return painter;
  }

  static void _drawLabelValue(
    Canvas canvas,
    double left,
    double right,
    double y,
    String label,
    String value,
    double size, {
    bool bold = false,
  }) {
    final double maxLabel = (right - left) * 0.62;
    final TextPainter labelP = _painter(
      _ellipsize(label, size, maxLabel),
      size: size,
      bold: bold,
    );
    final TextPainter valueP = _painter(value, size: size, bold: bold);
    labelP.paint(canvas, Offset(left, y - size));
    valueP.paint(canvas, Offset(right - valueP.width, y - size));
  }

  static void _drawColumns(
    Canvas canvas,
    double left,
    double right,
    double y,
    (String, String, String) cols,
    double size,
  ) {
    final (String qty, String name, String price) = cols;
    final double nameMax = (right - left) * 0.55;
    final TextPainter qtyP = _painter(qty, size: size);
    final TextPainter nameP = _painter(
      _ellipsize(name, size, nameMax),
      size: size,
      align: TextAlign.center,
    );
    final TextPainter priceP = _painter(price, size: size);
    qtyP.paint(canvas, Offset(left, y - size));
    nameP.paint(
      canvas,
      Offset((left + right) / 2 - nameP.width / 2, y - size),
    );
    priceP.paint(canvas, Offset(right - priceP.width, y - size));
  }

  static int _wrapLineCount(String text, double size, double maxWidth) {
    if (text.isEmpty) return 0;
    final List<String> words = text.split(' ');
    int lines = 1;
    String current = '';
    for (final String word in words) {
      final String next = current.isEmpty ? word : '$current $word';
      final TextPainter probe = _painter(next, size: size);
      if (probe.width > maxWidth && current.isNotEmpty) {
        lines++;
        current = word;
      } else {
        current = next;
      }
    }
    return lines;
  }

  static double _drawWrapped(
    Canvas canvas,
    String text, {
    required double size,
    required double left,
    required double startY,
    required double maxWidth,
    required double lineHeight,
    required bool center,
  }) {
    if (text.isEmpty) return startY;
    final List<String> words = text.split(' ');
    String current = '';
    double y = startY;
    final double cx = left + maxWidth / 2;
    for (final String word in words) {
      final String next = current.isEmpty ? word : '$current $word';
      final TextPainter probe = _painter(next, size: size);
      if (probe.width > maxWidth && current.isNotEmpty) {
        final TextPainter line = _painter(current, size: size);
        final double x = center ? cx - line.width / 2 : left;
        line.paint(canvas, Offset(x, y - size));
        y += lineHeight;
        current = word;
      } else {
        current = next;
      }
    }
    if (current.isNotEmpty) {
      final TextPainter line = _painter(current, size: size);
      final double x = center ? cx - line.width / 2 : left;
      line.paint(canvas, Offset(x, y - size));
      y += lineHeight;
    }
    return y;
  }

  static String _ellipsize(String text, double size, double maxWidth) {
    final TextPainter full = _painter(text, size: size);
    if (full.width <= maxWidth) return text;
    int end = text.length;
    while (end > 1) {
      final TextPainter probe = _painter('${text.substring(0, end)}…', size: size);
      if (probe.width <= maxWidth) return '${text.substring(0, end)}…';
      end--;
    }
    return '…';
  }
}

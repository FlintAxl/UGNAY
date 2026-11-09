import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Shared by the on-screen signature pad and the PNG export so they always look the same.
void drawSignatureStrokes(Canvas canvas, List<List<Offset>> strokes, {double width = 2.5}) {
  final line = Paint()
    ..color = Colors.black
    ..strokeCap = StrokeCap.round
    ..strokeWidth = width;
  final dot = Paint()..color = Colors.black;
  for (final s in strokes) {
    if (s.length == 1) canvas.drawCircle(s.first, width / 2, dot);
    for (int i = 0; i < s.length - 1; i++) {
      canvas.drawLine(s[i], s[i + 1], line);
    }
  }
}

class SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) => drawSignatureStrokes(canvas, strokes);

  @override
  bool shouldRepaint(covariant SignaturePainter oldDelegate) => true;
}

/// Renders the strokes at 3x the pad's size on a white background.
Future<Uint8List> exportSignaturePng(Size padSize, List<List<Offset>> strokes) async {
  const scale = 3.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  canvas.drawRect(Offset.zero & padSize, Paint()..color = Colors.white);
  drawSignatureStrokes(canvas, strokes);
  final image = await recorder.endRecording().toImage(
        (padSize.width * scale).round(),
        (padSize.height * scale).round(),
      );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

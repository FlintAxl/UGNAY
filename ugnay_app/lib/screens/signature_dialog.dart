import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api_client.dart';

class SignatureDialog extends StatefulWidget {
  final String rentalId;
  final String rentalNo;
  final String borrowerName;

  const SignatureDialog({
    super.key,
    required this.rentalId,
    required this.rentalNo,
    required this.borrowerName,
  });

  @override
  State<SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<SignatureDialog> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  bool _agreed = false;
  bool _busy = false;

  late Future<TermsData> _termsFuture;

  @override
  void initState() {
    super.initState();
    _termsFuture = getLogisticsTerms();
  }

  void _clearSignature() {
    setState(() {
      _strokes.clear();
      _currentStroke.clear();
    });
  }

  Future<void> _submit() async {
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The borrower must agree to the terms.')),
      );
      return;
    }

    if (_strokes.isEmpty && _currentStroke.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a signature above.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      // Render strokes to PNG
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 400, 200));

      // White background
      final bgPaint = Paint()..color = Colors.white;
      canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 200), bgPaint);

      // Signature strokes
      final strokePaint = Paint()
        ..color = Colors.black
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.0;

      for (final stroke in _strokes) {
        for (int i = 0; i < stroke.length - 1; i++) {
          canvas.drawLine(stroke[i], stroke[i + 1], strokePaint);
        }
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(400, 200);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      await signRental(widget.rentalId, agreed: true, imageBytes: bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signature recorded successfully!')),
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Signature Failed'),
          content: Text(e.message),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Contract & Signature: ${widget.rentalNo}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text('Borrower: ${widget.borrowerName}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              const Divider(height: 16),
              // Terms & Conditions list
              const Text('Terms & Conditions:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: FutureBuilder<TermsData>(
                    future: _termsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final terms = snapshot.data?.terms ?? [];
                      return ListView.separated(
                        itemCount: terms.length,
                        separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                        itemBuilder: (ctx, index) {
                          return Text(
                            '${index + 1}. ${terms[index]}',
                            style: const TextStyle(fontSize: 12),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Terms agreement checkbox
              CheckboxListTile(
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                title: const Text(
                  'The borrower has read and agreed to the cooperative rental terms.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
              const SizedBox(height: 8),
              // Signature Pad Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Borrower Signature Pad:', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _clearSignature,
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              // Signature canvas
              Container(
                height: 130,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _currentStroke = [details.localPosition];
                        _strokes.add(_currentStroke);
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _currentStroke.add(details.localPosition);
                      });
                    },
                    child: CustomPaint(
                      painter: _SignaturePainter(strokes: _strokes),
                      child: Container(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_busy ? 'Submitting...' : 'Confirm Signature'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _SignaturePainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;

    for (final stroke in strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

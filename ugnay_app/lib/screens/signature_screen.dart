import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api_client.dart';

/// Full-screen contract review + e-signature.
/// The borrower sees exactly what they agree to (items, total, down payment, due date,
/// terms) and then signs in the pad at the bottom.
class SignatureScreen extends StatefulWidget {
  final RentalDetail rental;

  const SignatureScreen({super.key, required this.rental});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final List<List<Offset>> _strokes = [];
  Size _padSize = const Size(400, 140); // updated from the pad's real size
  TermsData? _terms;
  String? _termsError;
  bool _agreed = false;
  bool _busy = false;

  RentalDetail get r => widget.rental;

  @override
  void initState() {
    super.initState();
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    setState(() => _termsError = null);
    try {
      final t = await getLogisticsTerms();
      if (mounted) setState(() => _terms = t);
    } on ApiException catch (e) {
      if (mounted) setState(() => _termsError = e.message);
    }
  }

  int get _pointCount => _strokes.fold<int>(0, (n, s) => n + s.length);

  void _clear() => setState(() => _strokes.clear());

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  /// Due date shown to the borrower: end of the 3rd day after pick-up.
  String _dueText(String pickupIso) {
    try {
      final dt = DateTime.parse(pickupIso).toLocal().add(const Duration(days: 3));
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} (end of day)';
    } catch (_) {
      return '3 days after pick-up';
    }
  }

  /// Renders the strokes at 3x the pad's size on a white background.
  Future<Uint8List> _exportPng() async {
    const scale = 3.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    canvas.drawRect(Offset.zero & _padSize, Paint()..color = Colors.white);
    _drawStrokes(canvas, _strokes);
    final image = await recorder.endRecording().toImage(
          (_padSize.width * scale).round(),
          (_padSize.height * scale).round(),
        );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _submit() async {
    if (_terms == null) {
      _snack('The terms could not be loaded yet. Tap Retry first.');
      return;
    }
    if (!_agreed) {
      _snack('The borrower must agree to the terms.');
      return;
    }
    if (_pointCount < 15) {
      _snack('Please sign inside the box.');
      return;
    }

    setState(() => _busy = true);
    try {
      final bytes = await _exportPng();
      await signRental(r.id, agreed: true, imageBytes: bytes);
      if (!mounted) return;
      _snack('Signature recorded.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Signature failed'),
          content: Text(e.message),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: TextStyle(color: Colors.grey.shade700))),
          Expanded(
            child: Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borrower = (r.memberName != null && r.memberName!.isNotEmpty)
        ? '${r.borrowerName} (member: ${r.memberName})'
        : r.borrowerName;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text('Contract: ${r.rentalNo}')),
        body: SafeArea(
          child: Column(
            children: [
              // ---- Scrollable review area ----
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _card('Rental summary', [
                      _row('Borrower', borrower),
                      _row('Venue', r.venue),
                      _row('Pick-up', _fmt(r.pickupAt)),
                      _row('Return by', _dueText(r.pickupAt)),
                    ]),
                    _card('Items (${r.items.length})', [
                      for (final i in r.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text('${i.quantity} ${i.unit} × ₱${i.unitPrice}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                  ],
                                ),
                              ),
                              Text('₱${i.amount}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      const Divider(height: 16),
                      _row('Total rental', '₱${r.rentalCost}', bold: true),
                      _row('50% down payment', '₱${r.minDownPayment}'),
                      const SizedBox(height: 4),
                      Text(
                        'Late return: 1% of the total rental cost per day after the due date. '
                        'Lost or damaged items are charged to the borrower.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ]),
                    _card('Terms & conditions', [
                      if (_terms != null)
                        for (int i = 0; i < _terms!.terms.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text('${i + 1}. ${_terms!.terms[i]}', style: const TextStyle(fontSize: 13)),
                          )
                      else if (_termsError != null) ...[
                        Text(_termsError!, style: TextStyle(color: theme.colorScheme.error)),
                        const SizedBox(height: 8),
                        OutlinedButton(onPressed: _loadTerms, child: const Text('Retry')),
                      ] else
                        const Center(
                          child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
                        ),
                    ]),
                  ],
                ),
              ),

              // ---- Fixed signing panel (outside the list, so drawing never scrolls) ----
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(top: BorderSide(color: theme.dividerColor)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CheckboxListTile(
                      value: _agreed,
                      onChanged: (_terms == null || _busy) ? null : (v) => setState(() => _agreed = v ?? false),
                      title: const Text(
                        'The borrower has read and agrees to the terms above.',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Borrower signature', style: TextStyle(fontWeight: FontWeight.bold)),
                        TextButton.icon(
                          onPressed: _busy ? null : _clear,
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                    Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LayoutBuilder(
                          builder: (context, c) {
                            _padSize = Size(c.maxWidth, c.maxHeight);
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: _busy ? null : (d) => setState(() => _strokes.add([d.localPosition])),
                              onPanUpdate: _busy ? null : (d) => setState(() => _strokes.last.add(d.localPosition)),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CustomPaint(painter: _SignaturePainter(_strokes)),
                                  if (_strokes.isEmpty)
                                    Center(
                                      child: IgnorePointer(
                                        child: Text('Sign here', style: TextStyle(color: Colors.grey.shade400)),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _submit,
                            icon: _busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check, size: 18),
                            label: Text(_busy ? 'Saving...' : 'Confirm signature'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared by the on-screen pad and the PNG export so they always look the same.
void _drawStrokes(Canvas canvas, List<List<Offset>> strokes, {double width = 2.5}) {
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

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) => _drawStrokes(canvas, strokes);

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
import 'package:flutter/material.dart';

import '../signature_pad.dart';

/// Full-screen signature capture for the PMES form.
///
/// Returns the drawn signature as PNG bytes when confirmed, or null when cancelled.
class PmesSignatureScreen extends StatefulWidget {
  const PmesSignatureScreen({super.key});

  @override
  State<PmesSignatureScreen> createState() => _PmesSignatureScreenState();
}

class _PmesSignatureScreenState extends State<PmesSignatureScreen> {
  final List<List<Offset>> _strokes = [];
  Size _padSize = const Size(400, 140);
  bool _busy = false;

  int get _pointCount => _strokes.fold<int>(0, (n, s) => n + s.length);

  void _clear() => setState(() => _strokes.clear());

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirm() async {
    if (_pointCount < 15) {
      _snack('Please sign inside the box.');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await exportSignaturePng(_padSize, _strokes);
      if (!mounted) return;
      Navigator.pop(context, bytes);
    } catch (_) {
      if (!mounted) return;
      _snack('Could not prepare the signature image.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Pirma')),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Sign here',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Draw your signature in the box below.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Signature', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                  CustomPaint(painter: SignaturePainter(_strokes)),
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
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(top: BorderSide(color: theme.dividerColor)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _confirm,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: Text(_busy ? 'Preparing...' : 'Use signature'),
                      ),
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

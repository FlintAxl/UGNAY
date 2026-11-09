import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../production_api.dart';
import 'production_widgets.dart';

const _maxPhotos = 6;

/// Records one bidder's ginger: supplier, type, weigh-in, good/bad kilos, price, photos.
class AddEntryScreen extends StatefulWidget {
  final String roundId;
  final String roundNo;

  const AddEntryScreen({super.key, required this.roundId, required this.roundNo});

  @override
  State<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<AddEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supplierCtrl = TextEditingController();
  final _weigh = TextEditingController();
  final _good = TextEditingController();
  final _bad = TextEditingController(text: '0');
  final _price = TextEditingController();
  final _remarks = TextEditingController();

  List<Supplier> _suppliers = [];
  bool _loadingSuppliers = true;
  String? _suppliersError;

  Supplier? _supplier;
  String? _kind; // NATIVE | HALF_NATIVE
  String? _supplierError;
  String? _kindError;

  final List<Uint8List> _photos = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // If the user edits the text after picking, the old selection no longer applies.
    _supplierCtrl.addListener(() {
      if (_supplier != null && _supplierCtrl.text != _supplier!.name) _supplier = null;
    });
    _loadSuppliers();
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _weigh.dispose();
    _good.dispose();
    _bad.dispose();
    _price.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    setState(() {
      _loadingSuppliers = true;
      _suppliersError = null;
    });
    try {
      final list = await listSuppliers(activeOnly: true);
      if (mounted) setState(() => _suppliers = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _suppliersError = e.message);
    } finally {
      if (mounted) setState(() => _loadingSuppliers = false);
    }
  }

  Future<void> _newSupplier() async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const SupplierDialog(),
    );
    if (data == null) return;
    try {
      final s = await createSupplier(
        name: data['name'] as String,
        phone: data['phone'] as String,
        address: data['address'] as String,
        notes: data['notes'] as String,
      );
      if (!mounted) return;
      setState(() {
        _suppliers = [..._suppliers, s]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _supplierCtrl.text = s.name;
        _supplier = s;
        _supplierError = null;
      });
    } on ApiException catch (e) {
      if (mounted) await showMessageDialog(context, 'Could not add supplier', e.message);
    }
  }

  Future<void> _addPhotos() async {
    final picked = await pickPhotos(context, maxCount: _maxPhotos - _photos.length);
    if (picked.isNotEmpty && mounted) setState(() => _photos.addAll(picked));
  }

  double _d(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0.0;

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    setState(() {
      _supplierError = _supplier == null ? 'Choose a supplier from the list' : null;
      _kindError = _kind == null ? 'Choose Native or Half Native' : null;
    });
    if (!valid || _supplier == null || _kind == null) return;

    final weigh = _d(_weigh), good = _d(_good), bad = _d(_bad), price = _d(_price);
    if (good + bad <= 0) {
      _snack('Enter the good and/or bad quality kilos.');
      return;
    }
    if (good + bad > weigh + 0.0001) {
      _snack('Good + bad kilos cannot be more than the weigh-in weight.');
      return;
    }

    final ok = await confirmDialog(
      context,
      title: 'Save entry',
      message: '${_supplier!.name} • ${kindLabel(_kind!)}\n'
          'Good: ${good.toStringAsFixed(2)} kg × ₱${price.toStringAsFixed(2)} = ₱${(good * price).toStringAsFixed(2)}\n'
          'Bad: ${bad.toStringAsFixed(2)} kg (not bought)\n\n'
          'Weights are locked after saving. To correct them, withdraw the entry and add it again.',
      confirmLabel: 'Save entry',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final round = await addBid(
        widget.roundId,
        supplierId: _supplier!.id,
        gingerKind: _kind!,
        weighInKg: weigh,
        goodKg: good,
        badKg: bad,
        pricePerKgGood: price,
        remarks: _remarks.text,
      );

      if (_photos.isNotEmpty) {
        final bidId = round.bids.last.bidId; // the server appends new entries at the end
        try {
          await uploadBidPhotos(widget.roundId, bidId, _photos);
        } on ApiException catch (e) {
          if (mounted) {
            await showMessageDialog(
              context,
              'Entry saved, photos not uploaded',
              '${e.message}\n\nYou can add the photos from the entry on the round screen.',
            );
          }
        }
      }

      if (!mounted) return;
      _snack('Entry saved for ${_supplier!.name}');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) await showMessageDialog(context, 'Could not save entry', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _numField(
    TextEditingController c,
    String label, {
    String? suffix,
    String? prefix,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: c,
      enabled: !_busy,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        prefixText: prefix,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
      validator: validator,
    );
  }

  Widget _photoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photos (${_photos.length}/$_maxPhotos)',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(
          'At least one photo is needed before this entry can be accepted.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < _photos.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_photos[i], width: 84, height: 84, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: InkWell(
                      onTap: _busy ? null : () => setState(() => _photos.removeAt(i)),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(3),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            if (_photos.length < _maxPhotos)
              InkWell(
                onTap: _busy ? null : _addPhotos,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weigh = _d(_weigh), good = _d(_good), bad = _d(_bad), price = _d(_price);
    final total = good * price;
    final used = good + bad;
    final over = weigh > 0 && used > weigh + 0.0001;
    final gap = weigh - used;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text('Add entry • ${widget.roundNo}')),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Weigh and grade this bidder\'s ginger first. Kilos are final once saved. '
                          'Only the good kilos are bought and priced.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Supplier
                if (_loadingSuppliers)
                  const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                else if (_suppliersError != null)
                  ErrorRetry(message: _suppliersError!, onRetry: _loadSuppliers)
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownMenu<Supplier>(
                          controller: _supplierCtrl,
                          enabled: !_busy,
                          expandedInsets: EdgeInsets.zero,
                          enableFilter: true,
                          requestFocusOnTap: true,
                          label: const Text('Supplier *'),
                          errorText: _supplierError,
                          dropdownMenuEntries: [
                            for (final s in _suppliers) DropdownMenuEntry(value: s, label: s.name),
                          ],
                          onSelected: (s) => setState(() {
                            _supplier = s;
                            _supplierError = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: IconButton.filledTonal(
                          tooltip: 'New supplier',
                          onPressed: _busy ? null : _newSupplier,
                          icon: const Icon(Icons.person_add_alt_1),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),

                // ---- Ginger type
                const Text('Ginger type *', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'NATIVE', label: Text('Native')),
                    ButtonSegment(value: 'HALF_NATIVE', label: Text('Half Native')),
                  ],
                  selected: _kind == null ? <String>{} : {_kind!},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() {
                            _kind = s.isEmpty ? null : s.first;
                            _kindError = null;
                          }),
                ),
                if (_kindError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(_kindError!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
                  ),
                const SizedBox(height: 16),

                // ---- Weights
                _numField(_weigh, 'Weigh-in (total kg) *', suffix: 'kg', validator: (v) {
                  final x = double.tryParse(v ?? '');
                  return (x == null || x <= 0) ? 'Enter the weigh-in weight' : null;
                }),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _numField(_good, 'Good *', suffix: 'kg', validator: (v) {
                        final x = double.tryParse(v ?? '');
                        return (x == null || x < 0) ? 'Required' : null;
                      }),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _numField(_bad, 'Bad *', suffix: 'kg', validator: (v) {
                        final x = double.tryParse(v ?? '');
                        return (x == null || x < 0) ? 'Required' : null;
                      }),
                    ),
                  ],
                ),
                if (over)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Good + bad (${used.toStringAsFixed(2)} kg) is more than the weigh-in '
                      '(${weigh.toStringAsFixed(2)} kg).',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                    ),
                  )
                else if (weigh > 0 && gap > 0.0001)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Unaccounted: ${gap.toStringAsFixed(2)} kg (dirt, soil, etc.)',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                const SizedBox(height: 12),
                _numField(_price, 'Price per kg (good quality) *', prefix: '₱ ', validator: (v) {
                  final x = double.tryParse(v ?? '');
                  return (x == null || x <= 0) ? 'Enter the price per kg' : null;
                }),
                const SizedBox(height: 12),

                // ---- Live total (display only; the server calculates the saved total)
                Card(
                  elevation: 1,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total price', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('₱${total.toStringAsFixed(2)}',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${good.toStringAsFixed(2)} kg good × ₱${price.toStringAsFixed(2)}. '
                          'Bad kilos are recorded but not bought.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarks,
                  enabled: !_busy,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Remarks (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _photoSection(),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(_busy ? 'Saving...' : 'Save entry'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
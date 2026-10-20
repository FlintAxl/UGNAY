import 'package:flutter/material.dart';

import '../api_client.dart';

class ReturnInspectionScreen extends StatefulWidget {
  final RentalDetail rental;

  const ReturnInspectionScreen({super.key, required this.rental});

  @override
  State<ReturnInspectionScreen> createState() => _ReturnInspectionScreenState();
}

class _ReturnItemEntry {
  final RentalDetailItem item;
  final TextEditingController returnedCtrl;
  final TextEditingController lostCtrl;
  final TextEditingController damagedCtrl;
  final TextEditingController chargeCtrl;

  _ReturnItemEntry({required this.item})
      : returnedCtrl = TextEditingController(
          text: item.unit == 'pc'
              ? (double.tryParse(item.quantity) ?? 0).toInt().toString()
              : item.quantity,
        ),
        lostCtrl = TextEditingController(text: '0'),
        damagedCtrl = TextEditingController(text: '0'),
        chargeCtrl = TextEditingController(text: '0.00');

  double get totalRented => double.tryParse(item.quantity) ?? 0.0;
  double get returned => double.tryParse(returnedCtrl.text) ?? 0.0;
  double get lost => double.tryParse(lostCtrl.text) ?? 0.0;
  double get damaged => double.tryParse(damagedCtrl.text) ?? 0.0;
  double get charge => double.tryParse(chargeCtrl.text) ?? 0.0;

  bool get isValidCount => (returned + lost + damaged - totalRented).abs() < 0.0001;
}

class _ReturnInspectionScreenState extends State<ReturnInspectionScreen> {
  final _formKey = GlobalKey<FormState>();
  late List<_ReturnItemEntry> _entries;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _entries = widget.rental.items.map((i) => _ReturnItemEntry(item: i)).toList();
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.returnedCtrl.dispose();
      e.lostCtrl.dispose();
      e.damagedCtrl.dispose();
      e.chargeCtrl.dispose();
    }
    super.dispose();
  }

  double get _totalCharges => _entries.fold(0.0, (acc, e) => acc + e.charge);

  Future<void> _submit({bool overrideWeekend = false}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    for (final e in _entries) {
      if (!e.isValidCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${e.item.name}: Returned (${e.returned}) + Lost (${e.lost}) + Damaged (${e.damaged}) must equal rented total (${e.totalRented}).',
            ),
          ),
        );
        return;
      }
      if (e.charge > 0 && (e.lost + e.damaged) == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${e.item.name}: A damage charge requires lost or damaged items.')),
        );
        return;
      }
    }

    setState(() => _busy = true);
    try {
      final lines = _entries.map((e) {
        return {
          'item_id': e.item.itemId,
          'returned': e.returned,
          'lost': e.lost,
          'damaged': e.damaged,
          'charge': e.charge,
        };
      }).toList();

      await returnRental(widget.rental.id, lines: lines, overrideWeekend: overrideWeekend);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rental return processed successfully!')),
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'WEEKEND_NOT_ALLOWED' && !overrideWeekend) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Weekend Return Warning'),
            content: Text(e.message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continue Anyway'),
              ),
            ],
          ),
        );
        if (proceed == true) {
          _submit(overrideWeekend: true);
          return;
        }
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Return Processing Failed'),
            content: Text(e.message),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Process Return: ${widget.rental.rentalNo}'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Notice banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Account for all rented items. Any lost or damaged items will be deducted from active stock.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Line item cards
              for (int i = 0; i < _entries.length; i++) ...[
                _buildInspectionCard(_entries[i], i),
                const SizedBox(height: 12),
              ],

              // Total damage charges preview
              if (_totalCharges > 0)
                Card(
                  elevation: 1,
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Lost/Damaged Charges:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('₱${_totalCharges.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              FilledButton.icon(
                onPressed: _busy ? null : () => _submit(),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.assignment_turned_in),
                label: Text(_busy ? 'Processing...' : 'Complete Return'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInspectionCard(_ReturnItemEntry entry, int index) {
    final item = entry.item;
    final isPc = item.unit == 'pc';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Text(
                  'Rented: ${item.quantity} ${item.unit}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                // Returned
                Expanded(
                  child: TextFormField(
                    controller: entry.returnedCtrl,
                    keyboardType: isPc
                        ? TextInputType.number
                        : const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Returned (${item.unit})',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                // Lost
                Expanded(
                  child: TextFormField(
                    controller: entry.lostCtrl,
                    keyboardType: isPc
                        ? TextInputType.number
                        : const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Lost (${item.unit})',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                // Damaged
                Expanded(
                  child: TextFormField(
                    controller: entry.damagedCtrl,
                    keyboardType: isPc
                        ? TextInputType.number
                        : const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Damaged (${item.unit})',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Charge input
            Row(
              children: [
                const Text('Loss / Damage Charge (₱): ', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    controller: entry.chargeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixText: '₱ ',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (!entry.isValidCount) ...[
              const SizedBox(height: 6),
              Text(
                'Count mismatch: Current total is ${(entry.returned + entry.lost + entry.damaged)} / ${entry.totalRented} ${item.unit}',
                style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


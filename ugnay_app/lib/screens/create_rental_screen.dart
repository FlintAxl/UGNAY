import 'package:flutter/material.dart';

import '../api_client.dart';
import 'rental_detail_screen.dart';

class CreateRentalScreen extends StatefulWidget {
  const CreateRentalScreen({super.key});

  @override
  State<CreateRentalScreen> createState() => _CreateRentalScreenState();
}

class _SelectedRentalLine {
  final InventoryItem item;
  double quantity;

  _SelectedRentalLine({required this.item, required this.quantity});

  double get unitPrice => double.tryParse(item.price) ?? 0.0;
  double get lineTotal => quantity * unitPrice;
}

class _CreateRentalScreenState extends State<CreateRentalScreen> {
  final _formKey = GlobalKey<FormState>();

  final _borrowerNameCtrl = TextEditingController();
  final _borrowerPhoneCtrl = TextEditingController();
  final _memberNameCtrl = TextEditingController();
  final _referredByCtrl = TextEditingController();
  final _venueCtrl = TextEditingController();

  DateTime _pickupAt = DateTime.now();
  final List<_SelectedRentalLine> _selectedLines = [];
  bool _busy = false;

  List<InventoryItem>? _availableItems;
  bool _loadingItems = false;

  @override
  void initState() {
    super.initState();
    _fetchInventory();
  }

  Future<void> _fetchInventory() async {
    setState(() => _loadingItems = true);
    try {
      final items = await listInventoryItems(activeOnly: true);
      if (mounted) setState(() => _availableItems = items);
    } catch (_) {
      // Handled in UI
    } finally {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  double get _totalCost {
    return _selectedLines.fold(0.0, (acc, line) => acc + line.lineTotal);
  }

  double get _minDownPayment {
    return _totalCost * 0.5;
  }

  Future<void> _selectPickupDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _pickupAt,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_pickupAt),
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _pickupAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hr = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hr:$min';
  }

  void _openAddItemModal() {
    final available = (_availableItems ?? []).where((item) {
      final isAlreadySelected = _selectedLines.any((l) => l.item.id == item.id);
      final hasStock = (double.tryParse(item.availableQuantity) ?? 0) > 0;
      return !isAlreadySelected && hasStock;
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          builder: (_, scrollCtrl) {
            if (_loadingItems) {
              return const Center(child: CircularProgressIndicator());
            }
            if (available.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No more items with available stock to add.',
                      style: TextStyle(color: Colors.grey)),
                ),
              );
            }
            return ListView.separated(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: available.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = available[index];
                return ListTile(
                  title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '₱${item.price} / ${item.unit} • Available: ${item.availableQuantity} ${item.unit}',
                  ),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedLines.add(_SelectedRentalLine(item: item, quantity: 1.0));
                    });
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_selectedLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item to the rental.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final itemsPayload = _selectedLines.map((l) {
        return {
          'item_id': l.item.id,
          'quantity': l.quantity,
        };
      }).toList();

      final created = await createRental(
        borrowerName: _borrowerNameCtrl.text.trim(),
        borrowerPhone: _borrowerPhoneCtrl.text.trim().isEmpty ? null : _borrowerPhoneCtrl.text.trim(),
        memberName: _memberNameCtrl.text.trim().isEmpty ? null : _memberNameCtrl.text.trim(),
        referredBy: _referredByCtrl.text.trim().isEmpty ? null : _referredByCtrl.text.trim(),
        venue: _venueCtrl.text.trim(),
        pickupAt: _pickupAt,
        items: itemsPayload,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Draft rental ${created.rentalNo} created!')),
      );

      // Navigate to detail screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => RentalDetailScreen(id: created.id)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Could not create rental'),
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
    return Scaffold(
      appBar: AppBar(title: const Text('New Rental')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Borrower Details Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Borrower & Event',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              )),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _borrowerNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Borrower Name *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().length < 2) ? 'Enter at least 2 characters' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _borrowerPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number (optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _memberNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Member Name (optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_outlined),
                          helperText: 'Leave empty if borrower is not a cooperative member.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _referredByCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Referred By (optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.handshake_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _venueCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Event Venue / Location *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().length < 2) ? 'Enter a valid venue' : null,
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: _selectPickupDateTime,
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Pick-up Date & Time *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                          child: Text(_formatDateTime(_pickupAt)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Selected Items Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Rented Items (${_selectedLines.length})',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  )),
                          FilledButton.tonalIcon(
                            onPressed: _busy ? null : _openAddItemModal,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Item'),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      if (_selectedLines.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text('No items added yet. Tap "Add Item" to select inventory.',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        )
                      else
                        for (int i = 0; i < _selectedLines.length; i++) ...[
                          _buildLineItemRow(i),
                          if (i < _selectedLines.length - 1)
                            const Divider(height: 12, thickness: 0.5),
                        ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Financial Summary Card
              Card(
                elevation: 1,
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Estimated Total Cost:',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          Text('₱${_totalCost.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Required 50% Down Payment:',
                              style: TextStyle(fontSize: 13, color: Colors.black87)),
                          Text('₱${_minDownPayment.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              )),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Cooperative rule: 50% deposit required at pickup. All equipment may be kept for up to 3 days.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Submit Button
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: Text(_busy ? 'Creating...' : 'Create Draft Rental'),
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

  Widget _buildLineItemRow(int index) {
    final line = _selectedLines[index];
    final maxAvail = double.tryParse(line.item.availableQuantity) ?? 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  '₱${line.item.price} / ${line.item.unit} • Max avail: ${line.item.availableQuantity}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    initialValue: line.item.unit == 'pc'
                        ? line.quantity.toInt().toString()
                        : line.quantity.toString(),
                    keyboardType: line.item.unit == 'pc'
                        ? TextInputType.number
                        : const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Qty (${line.item.unit})',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final val = double.tryParse(v ?? '');
                      if (val == null || val <= 0) return 'Invalid';
                      if (val > maxAvail) return 'Max $maxAvail';
                      if (line.item.unit == 'pc' && val != val.roundToDouble()) {
                        return 'Whole #';
                      }
                      return null;
                    },
                    onChanged: (v) {
                      final val = double.tryParse(v);
                      if (val != null && val > 0 && val <= maxAvail) {
                        setState(() => line.quantity = val);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${line.lineTotal.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                tooltip: 'Remove',
                onPressed: () {
                  setState(() => _selectedLines.removeAt(index));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}


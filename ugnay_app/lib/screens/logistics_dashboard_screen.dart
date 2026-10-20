import 'package:flutter/material.dart';

import '../api_client.dart';
import 'create_rental_screen.dart';
import 'home_screen.dart' show logout;
import 'rental_detail_screen.dart';

class LogisticsDashboardScreen extends StatefulWidget {
  final String fullName;

  const LogisticsDashboardScreen({super.key, required this.fullName});

  @override
  State<LogisticsDashboardScreen> createState() => _LogisticsDashboardScreenState();
}

class _LogisticsDashboardScreenState extends State<LogisticsDashboardScreen> {
  late Future<LogisticsSummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _reloadSummary();
  }

  void _reloadSummary() {
    setState(() {
      _summaryFuture = getLogisticsSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Logistics'),
              Text('Signed in as ${widget.fullName}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _reloadSummary,
            ),
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout),
              onPressed: () => logout(context),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.receipt_long), text: 'Rentals'),
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Inventory'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Top Summary Bar
            FutureBuilder<LogisticsSummary>(
              future: _summaryFuture,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final s = snapshot.data!;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _summaryChip('Active Out', s.out, Colors.blue),
                          const SizedBox(width: 8),
                          _summaryChip(
                            'Overdue',
                            s.overdue,
                            s.overdue > 0 ? Colors.red : Colors.grey,
                            isAlert: s.overdue > 0,
                          ),
                          const SizedBox(width: 8),
                          _summaryChip(
                            'Unpaid Returned',
                            s.unpaidReturned,
                            s.unpaidReturned > 0 ? Colors.orange : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          _summaryChip('Drafts', s.drafts, Colors.grey),
                          const SizedBox(width: 8),
                          _summaryChip('Active Items', s.activeItems, Colors.green),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            // Tab Contents
            Expanded(
              child: TabBarView(
                children: [
                  _RentalsTab(onRentalUpdated: _reloadSummary),
                  const _InventoryTab(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateRentalScreen()),
            );
            _reloadSummary();
          },
          icon: const Icon(Icons.add),
          label: const Text('New Rental'),
        ),
      ),
    );
  }

  Widget _summaryChip(String label, int count, MaterialColor color, {bool isAlert = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isAlert ? color.shade100 : color.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12, color: color.shade900)),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isAlert ? color.shade900 : color.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================ Rentals Tab

class _RentalsTab extends StatefulWidget {
  final VoidCallback onRentalUpdated;

  const _RentalsTab({required this.onRentalUpdated});

  @override
  State<_RentalsTab> createState() => _RentalsTabState();
}

class _RentalsTabState extends State<_RentalsTab> {
  String _selectedStatus = 'OUT';
  final _searchController = TextEditingController();
  late Future<List<RentalSummary>> _future;

  static const _statusOptions = [
    {'value': 'OUT', 'label': 'Active Out'},
    {'value': 'OVERDUE', 'label': 'Overdue'},
    {'value': 'UNPAID', 'label': 'Unpaid'},
    {'value': 'DRAFT', 'label': 'Drafts'},
    {'value': 'RETURNED', 'label': 'Returned'},
    {'value': 'ALL', 'label': 'All'},
  ];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = listRentals(status: _selectedStatus, q: _searchController.text);
    });
  }

  String _formatDate(String iso) {
    if (iso.length >= 10) return iso.substring(0, 10);
    return iso;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'RELEASED':
        return Colors.blue.shade700;
      case 'RETURNED':
        return Colors.green.shade700;
      case 'CANCELLED':
        return Colors.grey.shade600;
      case 'DRAFT':
      default:
        return Colors.orange.shade800;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Status Filter Chips
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final opt in _statusOptions)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(opt['label']!),
                      selected: _selectedStatus == opt['value'],
                      onSelected: (selected) {
                        if (selected && _selectedStatus != opt['value']) {
                          setState(() => _selectedStatus = opt['value']!);
                          _reload();
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search borrower, member, or rental #',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _reload();
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (_) => _reload(),
          ),
        ),
        // List of Rentals
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _reload();
              widget.onRentalUpdated();
            },
            child: FutureBuilder<List<RentalSummary>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(snapshot.error.toString(), textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _reload, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  );
                }

                final rentals = snapshot.data ?? [];
                if (rentals.isEmpty) {
                  return const Center(
                    child: Text('No rentals found under this filter.',
                        style: TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: rentals.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final r = rentals[index];
                    final hasBalance = (double.tryParse(r.balance) ?? 0) > 0;

                    return Card(
                      elevation: 0.8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RentalDetailScreen(id: r.id),
                            ),
                          );
                          if (mounted) {
                            _reload();
                            widget.onRentalUpdated();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    r.rentalNo,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _statusColor(r.status).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _statusColor(r.status)),
                                    ),
                                    child: Text(
                                      r.status,
                                      style: TextStyle(
                                        color: _statusColor(r.status),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (r.memberName != null && r.memberName!.isNotEmpty)
                                    ? '${r.borrowerName} (${r.memberName})'
                                    : r.borrowerName,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Pickup: ${_formatDate(r.pickupAt)}${r.dueAt != null ? ' • Due: ${_formatDate(r.dueAt!)}' : ''}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${r.itemCount} item(s)',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                              if (r.isOverdue) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.error_outline,
                                        size: 14, color: Theme.of(context).colorScheme.error),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${r.daysLate} day(s) late',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const Divider(height: 12, thickness: 0.5),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Total: ₱${r.totalDue}',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text(
                                    hasBalance ? 'Balance: ₱${r.balance}' : 'Paid in full',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: hasBalance
                                          ? Theme.of(context).colorScheme.primary
                                          : Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================ Inventory Tab

class _InventoryTab extends StatefulWidget {
  const _InventoryTab();

  @override
  State<_InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<_InventoryTab> {
  String? _category;
  final _searchController = TextEditingController();
  late Future<List<InventoryItem>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = listInventoryItems(category: _category, q: _searchController.text);
    });
  }

  Future<void> _adjustStock(InventoryItem item) async {
    final controller = TextEditingController(text: item.totalQuantity);
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Adjust Stock: ${item.name}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Currently Rented Out: ${item.outQuantity} ${item.unit}'),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                keyboardType: item.unit == 'pc'
                    ? TextInputType.number
                    : const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'New Total Owned Quantity (${item.unit})',
                  border: const OutlineInputBorder(),
                  helperText: 'Must be at least ${item.outQuantity} (items out).',
                ),
                validator: (val) {
                  final v = double.tryParse(val ?? '');
                  if (v == null || v < 0) return 'Enter a valid quantity';
                  final out = double.tryParse(item.outQuantity) ?? 0;
                  if (v < out) return 'Cannot be lower than currently rented ($out)';
                  if (item.unit == 'pc' && v != v.roundToDouble()) {
                    return 'Pieces must be whole numbers';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save Stock'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final newQty = double.tryParse(controller.text) ?? 0;
    try {
      await setInventoryStock(item.id, newQty);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated total stock of ${item.name} to $newQty')),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Stock Update Failed'),
          content: Text(e.message),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }

  Future<void> _addItem() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    String category = 'EQUIPMENT';
    String unit = 'pc';
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Inventory Item'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Item Name *', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Min 2 characters' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'EQUIPMENT', child: Text('Equipment')),
                      DropdownMenuItem(value: 'COVER_AND_TELA', child: Text('Cover & Tela')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => category = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: unit,
                    decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'pc', child: Text('Piece (pc)')),
                      DropdownMenuItem(value: 'yard', child: Text('Yard')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => unit = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Rental Price (₱) *',
                      border: OutlineInputBorder(),
                      prefixText: '₱ ',
                    ),
                    validator: (v) {
                      final val = double.tryParse(v ?? '');
                      if (val == null || val < 0) return 'Valid price required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: qtyCtrl,
                    keyboardType: unit == 'pc' ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Initial Total Quantity ($unit) *',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final val = double.tryParse(v ?? '');
                      if (val == null || val < 0) return 'Valid quantity required';
                      if (unit == 'pc' && val != val.roundToDouble()) return 'Must be a whole piece';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Create Item'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    try {
      final price = double.tryParse(priceCtrl.text) ?? 0.0;
      final qty = double.tryParse(qtyCtrl.text) ?? 0.0;
      await createInventoryItem(
        name: nameCtrl.text.trim(),
        category: category,
        unit: unit,
        price: price,
        totalQuantity: qty,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Item ${nameCtrl.text.toUpperCase()} created')),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Failed to add item'),
          content: Text(e.message),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }

  Future<void> _editItem(InventoryItem item) async {
    final nameCtrl = TextEditingController(text: item.name);
    final priceCtrl = TextEditingController(text: item.price);
    bool isActive = item.isActive;
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit: ${item.name}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Item Name *', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Min 2 characters' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Rental Price (₱) *',
                    border: OutlineInputBorder(),
                    prefixText: '₱ ',
                  ),
                  validator: (v) {
                    final val = double.tryParse(v ?? '');
                    if (val == null || val < 0) return 'Valid price required';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Active for Rental'),
                  subtitle: Text(
                    isActive ? 'Available to select' : 'Hidden from rental creation',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: isActive,
                  onChanged: (v) => setDialogState(() => isActive = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    try {
      final price = double.tryParse(priceCtrl.text) ?? 0.0;
      await updateInventoryItem(
        item.id,
        name: nameCtrl.text.trim(),
        price: price,
        isActive: isActive,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Item ${item.name} updated')),
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Failed to update item'),
          content: Text(e.message),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Category Chips
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _category == null,
                onSelected: (selected) {
                  if (selected && _category != null) {
                    setState(() => _category = null);
                    _reload();
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Equipment'),
                selected: _category == 'EQUIPMENT',
                onSelected: (selected) {
                  if (selected && _category != 'EQUIPMENT') {
                    setState(() => _category = 'EQUIPMENT');
                    _reload();
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Cover & Tela'),
                selected: _category == 'COVER_AND_TELA',
                onSelected: (selected) {
                  if (selected && _category != 'COVER_AND_TELA') {
                    setState(() => _category = 'COVER_AND_TELA');
                    _reload();
                  }
                },
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _addItem,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Item', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
              ),
            ],
          ),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search items by name',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _reload();
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (_) => _reload(),
          ),
        ),
        // Inventory List
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: FutureBuilder<List<InventoryItem>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(snapshot.error.toString(), textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _reload, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  );
                }

                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No inventory items found.', style: TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final avail = double.tryParse(item.availableQuantity) ?? 0;

                    return Card(
                      elevation: 0.8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Text(
                                  '₱${item.price} / ${item.unit}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  item.category.replaceAll('_', ' '),
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                                const Spacer(),
                                if (!item.isActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Inactive',
                                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  ),
                              ],
                            ),
                            const Divider(height: 12, thickness: 0.5),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Total: ${item.totalQuantity} ${item.unit}',
                                        style: const TextStyle(fontSize: 12)),
                                    Text('Out: ${item.outQuantity} ${item.unit}',
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.orange.shade800)),
                                    Text('Available: ${item.availableQuantity} ${item.unit}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: avail > 0 ? Colors.green.shade800 : Colors.red,
                                        )),
                                  ],
                                ),
                                Row(
                                  children: [
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                      onPressed: () => _editItem(item),
                                      icon: const Icon(Icons.edit_note, size: 16),
                                      label: const Text('Edit', style: TextStyle(fontSize: 12)),
                                    ),
                                    const SizedBox(width: 6),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                      onPressed: () => _adjustStock(item),
                                      icon: const Icon(Icons.inventory, size: 16),
                                      label: const Text('Stock', style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}


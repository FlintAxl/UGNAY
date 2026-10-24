import 'package:flutter/material.dart';

import '../api_client.dart';
import 'return_inspection_screen.dart';
import 'signature_screen.dart';

class RentalDetailScreen extends StatefulWidget {
  final String id;

  const RentalDetailScreen({super.key, required this.id});

  @override
  State<RentalDetailScreen> createState() => _RentalDetailScreenState();
}

class _RentalDetailScreenState extends State<RentalDetailScreen> {
  late Future<RentalDetail> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = getRentalDetail(widget.id);
  }

  void _reload() {
    setState(() {
      _future = getRentalDetail(widget.id);
    });
  }

  Future<void> _message(String title, String text) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final y = dt.year;
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hr = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d $hr:$min';
    } catch (_) {
      return iso.length >= 10 ? iso.substring(0, 10) : iso;
    }
  }

  Color _statusColor(String status, BuildContext context) {
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

  Future<void> _recordPayment(RentalDetail r) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final balanceNum = double.tryParse(r.balance) ?? 0.0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Payment'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Outstanding balance: ₱${r.balance}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (r.status == 'DRAFT') ...[
                const SizedBox(height: 4),
                Text('Required 50% down payment: ₱${r.minDownPayment}',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (₱)',
                  border: OutlineInputBorder(),
                  prefixText: '₱ ',
                ),
                validator: (val) {
                  final v = double.tryParse(val ?? '');
                  if (v == null || v <= 0) return 'Enter a valid amount';
                  if (v > balanceNum + 0.001) {
                    return 'Cannot exceed balance (₱${r.balance})';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLength: 200,
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
            child: const Text('Save Payment'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final amt = double.tryParse(amountController.text) ?? 0.0;
    setState(() => _busy = true);
    try {
      await addRentalPayment(r.id, amount: amt, note: noteController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment of ₱${amt.toStringAsFixed(2)} recorded')),
      );
      _reload();
    } on ApiException catch (e) {
      if (mounted) await _message('Payment Failed', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

Future<void> _releaseRental(RentalDetail r, {bool overrideWeekend = false}) async {
  if (!overrideWeekend) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release Rental Items'),
        content: Text(
          'Confirm release of ${r.itemCount} item(s) to ${r.borrowerName}?\n\n'
          'Pickup date will start the 3-day rental period.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm Release')),
        ],
      ),
    );
    if (ok != true) return;
  }

  setState(() => _busy = true);
  try {
    await releaseRental(r.id, overrideWeekend: overrideWeekend);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rental ${r.rentalNo} released successfully!')),
    );
    _reload();
  } on ApiException catch (e) {
    if (!mounted) return;
    if (e.code == 'WEEKEND_NOT_ALLOWED' && !overrideWeekend) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Weekend Release Warning'),
          content: Text(e.message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue Anyway')),
          ],
        ),
      );
      if (proceed == true) {
        await _releaseRental(r, overrideWeekend: true);
        return;
      }
    } else {
      await _message('Could not release', e.message);
    }
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}

  Future<void> _cancelRental(RentalDetail r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Rental'),
        content: Text('Are you sure you want to cancel rental ${r.rentalNo} for ${r.borrowerName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Rental')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Rental'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await cancelRental(r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rental ${r.rentalNo} cancelled')),
      );
      _reload();
    } on ApiException catch (e) {
      if (mounted) await _message('Could not cancel', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black87)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: color ?? Colors.black87,
              )),
          Text('₱$value',
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: color ?? Colors.black87,
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rental Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _reload,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<RentalDetail>(
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

            final r = snapshot.data!;
            final hasBalance = (double.tryParse(r.balance) ?? 0) > 0;
            final canCancel = r.status == 'DRAFT' && ((double.tryParse(r.totalPaid) ?? 0) == 0);

            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header Card with Status
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
                              Text(r.rentalNo,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      )),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(r.status, context).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _statusColor(r.status, context)),
                                ),
                                child: Text(
                                  r.status,
                                  style: TextStyle(
                                    color: _statusColor(r.status, context),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (r.isOverdue) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      size: 18, color: Theme.of(context).colorScheme.error),
                                  const SizedBox(width: 6),
                                  Text(
                                    'OVERDUE: ${r.daysLate} day(s) late (Penalty: ₱${r.penalty})',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onErrorContainer,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Borrower & Event Info Card
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
                          const Divider(height: 16),
                          _infoRow(Icons.person, 'Borrower', r.borrowerName),
                          if (r.borrowerPhone != null && r.borrowerPhone!.isNotEmpty)
                            _infoRow(Icons.phone, 'Phone', r.borrowerPhone!),
                          if (r.memberName != null && r.memberName!.isNotEmpty)
                            _infoRow(Icons.badge, 'Member', r.memberName!),
                          if (r.referredBy != null && r.referredBy!.isNotEmpty)
                            _infoRow(Icons.handshake, 'Referred By', r.referredBy!),
                          _infoRow(Icons.location_on, 'Venue', r.venue),
                          _infoRow(Icons.schedule, 'Pickup At', _formatDate(r.pickupAt)),
                          _infoRow(Icons.event, 'Due At', _formatDate(r.dueAt)),
                          if (r.releasedAt != null)
                            _infoRow(Icons.output, 'Released', _formatDate(r.releasedAt)),
                          if (r.returnedAt != null)
                            _infoRow(Icons.input, 'Returned', _formatDate(r.returnedAt)),
                          if (r.preparedByName != null)
                            _infoRow(Icons.edit_note, 'Prepared By', r.preparedByName!),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Items Card
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Items (${r.items.length})',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  )),
                          const Divider(height: 16),
                          for (final item in r.items) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.name,
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Text('₱${item.amount}',
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item.quantity} ${item.unit} @ ₱${item.unitPrice} / ${item.unit}',
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                  ),
                                  if (r.status == 'RETURNED') ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Returned: ${item.returned} | Lost: ${item.lost} | Damaged: ${item.damaged}'
                                      '${(double.tryParse(item.charge) ?? 0) > 0 ? ' (Charge: ₱${item.charge})' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: (double.tryParse(item.lost) ?? 0) > 0 ||
                                                (double.tryParse(item.damaged) ?? 0) > 0
                                            ? Theme.of(context).colorScheme.error
                                            : Colors.green.shade800,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (item != r.items.last) const Divider(height: 8, thickness: 0.5),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Financial Breakdown Card
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Financials',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  )),
                          const Divider(height: 16),
                          _moneyRow('Rental Cost', r.rentalCost),
                          if ((double.tryParse(r.penalty) ?? 0) > 0)
                            _moneyRow('Late Penalty (${r.daysLate}d)', r.penalty,
                                color: Theme.of(context).colorScheme.error),
                          if ((double.tryParse(r.otherCharges) ?? 0) > 0)
                            _moneyRow('Damage/Lost Charges', r.otherCharges,
                                color: Theme.of(context).colorScheme.error),
                          const Divider(height: 12),
                          _moneyRow('Total Due', r.totalDue, bold: true),
                          _moneyRow('Total Paid', r.totalPaid),
                          const Divider(height: 12),
                          _moneyRow(
                            'Balance Remaining',
                            r.balance,
                            bold: true,
                            color: hasBalance
                                ? Theme.of(context).colorScheme.primary
                                : Colors.green.shade700,
                          ),
                          if (r.status == 'DRAFT') ...[
                            const SizedBox(height: 6),
                            Text(
                              'Minimum 50% down payment required: ₱${r.minDownPayment}',
                              style: TextStyle(
                                fontSize: 12,
                                color: (double.tryParse(r.totalPaid) ?? 0) >=
                                        (double.tryParse(r.minDownPayment) ?? 0)
                                    ? Colors.green.shade800
                                    : Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Payments History Card
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
                              Text('Payment History (${r.payments.length})',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      )),
                              if (hasBalance && r.status != 'CANCELLED')
                                TextButton.icon(
                                  onPressed: _busy ? null : () => _recordPayment(r),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add Payment'),
                                ),
                            ],
                          ),
                          const Divider(height: 16),
                          if (r.payments.isEmpty)
                            const Text('No payments recorded yet.',
                                style: TextStyle(color: Colors.grey))
                          else
                            for (final p in r.payments) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.kind.replaceAll('_', ' '),
                                            style: const TextStyle(fontWeight: FontWeight.w600)),
                                        Text(
                                          '${_formatDate(p.at)}${p.receivedByName != null ? ' • by ${p.receivedByName}' : ''}',
                                          style: TextStyle(
                                              fontSize: 12, color: Colors.grey.shade700),
                                        ),
                                        if (p.note != null && p.note!.isNotEmpty)
                                          Text('Note: ${p.note}',
                                              style: TextStyle(
                                                  fontSize: 12, color: Colors.grey.shade600)),
                                      ],
                                    ),
                                    Text('₱${p.amount}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, color: Colors.green)),
                                  ],
                                ),
                              ),
                              if (p != r.payments.last) const Divider(height: 8, thickness: 0.5),
                            ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Borrower Signature Card
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Contract & Signature',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  )),
                          const Divider(height: 16),
                          if (r.signature == null)
                            const Text('Not signed yet.', style: TextStyle(color: Colors.grey))
                          else ...[
                            Text(
                              'Signed by ${r.signature!.signedByName} on ${_formatDate(r.signature!.signedAt)} (Terms v${r.signature!.termsVersion})',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                r.signature!.url,
                                height: 120,
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, err, stack) =>
                                    const Text('Signature preview unavailable'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Contextual Actions Section
                  const SizedBox(height: 20),
                  if (r.status == 'DRAFT') ...[
                    if (r.signature == null) ...[
                      FilledButton.tonalIcon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final ok = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  fullscreenDialog: true,
                                  builder: (_) => SignatureScreen(rental: r),
                                ),
                              );
                                if (ok == true) _reload();
                              },
                        icon: const Icon(Icons.draw_outlined),
                        label: const Text('Sign Contract & Terms'),
                      ),
                      const SizedBox(height: 10),
                    ],
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _releaseRental(r),
                      icon: const Icon(Icons.output),
                      label: const Text('Release Items'),
                    ),
                  ] else if (r.status == 'RELEASED') ...[
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final ok = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ReturnInspectionScreen(rental: r),
                                ),
                              );
                              if (ok == true) _reload();
                            },
                      icon: const Icon(Icons.assignment_turned_in_outlined),
                      label: const Text('Process Return'),
                    ),
                  ] else if (r.status == 'RETURNED' && hasBalance) ...[
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _recordPayment(r),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Settle Remaining Balance'),
                    ),
                  ],

                  if (canCancel) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _cancelRental(r),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel Rental'),
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}


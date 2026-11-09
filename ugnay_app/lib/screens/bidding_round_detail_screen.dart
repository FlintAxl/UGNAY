import 'package:flutter/material.dart';

import '../api_client.dart';
import '../production_api.dart';
import 'add_entry_screen.dart';
import 'production_widgets.dart';

const _maxPhotos = 6;

class BiddingRoundDetailScreen extends StatefulWidget {
  final String id;

  const BiddingRoundDetailScreen({super.key, required this.id});

  @override
  State<BiddingRoundDetailScreen> createState() => _BiddingRoundDetailScreenState();
}

class _BiddingRoundDetailScreenState extends State<BiddingRoundDetailScreen> {
  late Future<BiddingRound> _future;
  final Set<String> _selected = {};
  String _sort = 'price'; // price | good | entered
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = getRound(widget.id);
  }

  void _reload() => setState(() => _future = getRound(widget.id));

  /// Runs an API action with the busy bar, shows errors, then reloads.
  Future<void> _run(Future<void> Function() action, {String errorTitle = 'Action failed'}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _reload();
    } on ApiException catch (e) {
      if (mounted) await showMessageDialog(context, errorTitle, e.message);
      if (mounted) _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------ actions

  Future<void> _addEntry(BiddingRound r) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddEntryScreen(roundId: r.id, roundNo: r.roundNo)),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _withdraw(BiddingRound r, BidEntry e) async {
    final ok = await confirmDialog(
      context,
      title: 'Withdraw entry',
      message: 'Withdraw ${e.supplierName}\'s ${kindLabel(e.gingerKind)} entry?\n\n'
          'Weights are locked, so to correct them you withdraw this entry and add it again.',
      confirmLabel: 'Withdraw',
      destructive: true,
    );
    if (!ok) return;
    _selected.remove(e.bidId);
    await _run(() async {
      await withdrawBid(r.id, e.bidId);
    }, errorTitle: 'Could not withdraw');
  }

  Future<void> _editEntry(BiddingRound r, BidEntry e) async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditEntryDialog(entry: e),
    );
    if (data == null) return;
    await _run(() async {
      await updateBid(r.id, e.bidId,
          pricePerKgGood: data['price'] as double, remarks: data['remarks'] as String);
    }, errorTitle: 'Could not update entry');
  }

  Future<void> _addPhotos(BiddingRound r, BidEntry e) async {
    final remaining = _maxPhotos - e.photos.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This entry already has the maximum of 6 photos.')),
      );
      return;
    }
    final photos = await pickPhotos(context, maxCount: remaining);
    if (photos.isEmpty || !mounted) return;
    await _run(() async {
      await uploadBidPhotos(r.id, e.bidId, photos);
    }, errorTitle: 'Could not upload photos');
  }

  Future<void> _deletePhoto(BiddingRound r, BidEntry e, EntryPhoto p) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove photo',
      message: 'Remove this photo from ${e.supplierName}\'s entry?',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    await _run(() async {
      await deleteBidPhoto(r.id, e.bidId, p.photoId);
    }, errorTitle: 'Could not remove photo');
  }

  Future<void> _award(BiddingRound r) async {
    final picked = r.bids.where((b) => _selected.contains(b.bidId)).toList();
    final remarks = await showDialog<String>(
      context: context,
      builder: (_) => _AwardDialog(entries: picked),
    );
    if (remarks == null) return;
    await _run(() async {
      await awardRound(r.id, acceptedBidIds: picked.map((b) => b.bidId).toList(), remarks: remarks);
      _selected.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Round ${r.roundNo} awarded')),
        );
      }
    }, errorTitle: 'Could not award round');
  }

  Future<void> _cancelRound(BiddingRound r) async {
    final ok = await confirmDialog(
      context,
      title: 'Cancel round',
      message: 'Cancel ${r.roundNo}? No entry will be accepted and the round will be closed.',
      confirmLabel: 'Cancel round',
      destructive: true,
    );
    if (!ok) return;
    await _run(() async {
      await cancelRound(r.id);
    }, errorTitle: 'Could not cancel');
  }

  // ------------------------------------------------------------ helpers

  List<BidEntry> _sortedActive(List<BidEntry> bids) {
    final list = bids.where((b) => b.status != 'WITHDRAWN').toList();
    if (_sort == 'price') {
      list.sort((a, b) => a.priceNum.compareTo(b.priceNum));
    } else if (_sort == 'good') {
      list.sort((a, b) => b.goodKgNum.compareTo(a.goodKgNum));
    }
    return list;
  }

  Widget _stat(String label, String value, {Color? color, bool bold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        Text(value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color,
            )),
      ],
    );
  }

  Widget _thumb(BiddingRound r, BidEntry e, EntryPhoto p, bool editable) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          InkWell(
            onTap: () => showPhotoZoom(context, p.url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                p.url,
                width: 76,
                height: 76,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const SizedBox(width: 76, height: 76, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                errorBuilder: (context, error, stack) => Container(
                  width: 76,
                  height: 76,
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
          if (editable)
            Positioned(
              top: 0,
              right: 0,
              child: InkWell(
                onTap: _busy ? null : () => _deletePhoto(r, e, p),
                child: Container(
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(3),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _entryCard(BiddingRound r, BidEntry e) {
    final theme = Theme.of(context);
    final open = r.status == 'OPEN';
    final editable = open && e.status == 'SUBMITTED';
    final hasPhotos = e.photos.isNotEmpty;
    final accepted = e.status == 'ACCEPTED';
    final rejected = e.status == 'REJECTED';

    return Card(
      elevation: 1,
      color: accepted ? Colors.green.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accepted ? Colors.green.shade400 : Colors.transparent),
      ),
      child: Opacity(
        opacity: rejected ? 0.65 : 1,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(e.supplierName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  StatusChip(e.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(kindLabel(e.gingerKind),
                  style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _stat('Weigh-in', '${e.weighInKg} kg')),
                  Expanded(
                      child: _stat('Good', '${e.goodKg} kg',
                          color: Colors.green.shade800, bold: true)),
                  Expanded(child: _stat('Bad (not bought)', '${e.badKg} kg', color: Colors.grey.shade700)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _stat('Price / kg (good)', '₱${e.pricePerKgGood}')),
                  Expanded(child: _stat('Total price', '₱${e.totalPrice}', bold: true)),
                ],
              ),
              if (e.remarks != null && e.remarks!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Remarks: ${e.remarks}', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
              ],
              const SizedBox(height: 10),
              if (hasPhotos)
                SizedBox(
                  height: 76,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [for (final p in e.photos) _thumb(r, e, p, editable)],
                  ),
                )
              else
                Text(
                  editable ? 'No photos yet. Add at least one to accept this entry.' : 'No photos.',
                  style: TextStyle(fontSize: 12, color: editable ? theme.colorScheme.error : Colors.grey),
                ),
              if (editable) ...[
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: _selected.contains(e.bidId),
                  onChanged: (hasPhotos && !_busy)
                      ? (v) => setState(() {
                            if (v == true) {
                              _selected.add(e.bidId);
                            } else {
                              _selected.remove(e.bidId);
                            }
                          })
                      : null,
                  title: Text(hasPhotos ? 'Select to accept' : 'Add a photo to enable selection',
                      style: const TextStyle(fontSize: 13)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : () => _addPhotos(r, e),
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: const Text('Photos'),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _editEntry(r, e),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit price'),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _withdraw(r, e),
                      style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Withdraw'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultCard(BiddingRound r) {
    return Card(
      elevation: 1,
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.shade400),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Final result',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(child: _stat('Final kilos (good)', '${r.acceptedGoodKg} kg', bold: true, color: Colors.green.shade900)),
                Expanded(child: _stat('Total price', '₱${r.acceptedTotalPrice}', bold: true, color: Colors.green.shade900)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${r.acceptedCount} accepted entr${r.acceptedCount == 1 ? 'y' : 'ies'}. Bad-quality kilos '
              '(${r.acceptedBadKg} kg) were not bought and are not counted.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
            if (r.awardRemarks != null && r.awardRemarks!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Reason: ${r.awardRemarks}', style: const TextStyle(fontSize: 13)),
            ],
            if (r.awardedByName != null) ...[
              const SizedBox(height: 4),
              Text('Awarded by ${r.awardedByName}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _selectionBar(BiddingRound r) {
    final picked = r.bids.where((b) => _selected.contains(b.bidId)).toList();
    final kg = picked.fold<double>(0, (s, b) => s + b.goodKgNum);
    final total = picked.fold<double>(0, (s, b) => s + b.totalPriceNum);
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${picked.length} selected', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${kg.toStringAsFixed(2)} kg good • ₱${total.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: (_busy || picked.isEmpty) ? null : () => _award(r),
                icon: const Icon(Icons.check),
                label: const Text('Accept selected'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bidding Round'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _reload,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<BiddingRound>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ErrorRetry(message: snapshot.error.toString(), onRetry: _reload);
            }
            final r = snapshot.data!;
            final open = r.status == 'OPEN';
            final active = _sortedActive(r.bids);
            final withdrawn = r.bids.where((b) => b.status == 'WITHDRAWN').toList();

            return Column(
              children: [
                if (_busy) const LinearProgressIndicator(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
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
                                    Text(r.roundNo,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(fontWeight: FontWeight.bold)),
                                    StatusChip(r.status),
                                  ],
                                ),
                                if (r.title != null && r.title!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(r.title!, style: const TextStyle(fontWeight: FontWeight.w500)),
                                ],
                                const SizedBox(height: 4),
                                Text('Bidding date: ${r.biddingDate}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                if (r.createdByName != null)
                                  Text('Opened by ${r.createdByName}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                if (r.notes != null && r.notes!.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(r.notes!, style: const TextStyle(fontSize: 13)),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (r.status == 'AWARDED') ...[
                          _resultCard(r),
                          const SizedBox(height: 12),
                        ],
                        if (r.status == 'CANCELLED')
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text('This round was cancelled. No entry was accepted.',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Entries (${active.length})',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            if (open)
                              FilledButton.tonalIcon(
                                onPressed: _busy ? null : () => _addEntry(r),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add entry'),
                              ),
                          ],
                        ),
                        if (active.length > 1) ...[
                          const SizedBox(height: 8),
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: 'price', label: Text('Lowest price')),
                              ButtonSegment(value: 'good', label: Text('Most good kg')),
                              ButtonSegment(value: 'entered', label: Text('Entered')),
                            ],
                            selected: {_sort},
                            onSelectionChanged: (s) => setState(() => _sort = s.first),
                          ),
                        ],
                        const SizedBox(height: 8),
                        if (active.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: Text('No entries yet. Tap "Add entry" for each bidder.',
                                  style: TextStyle(color: Colors.grey)),
                            ),
                          )
                        else
                          for (final e in active) ...[
                            _entryCard(r, e),
                            const SizedBox(height: 10),
                          ],
                        if (withdrawn.isNotEmpty)
                          ExpansionTile(
                            title: Text('Withdrawn entries (${withdrawn.length})',
                                style: const TextStyle(fontSize: 14)),
                            children: [
                              for (final e in withdrawn)
                                ListTile(
                                  dense: true,
                                  title: Text('${e.supplierName} • ${kindLabel(e.gingerKind)}'),
                                  subtitle: Text('${e.goodKg} kg good @ ₱${e.pricePerKgGood}'),
                                ),
                            ],
                          ),
                        if (open) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _cancelRound(r),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.error,
                            ),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel round'),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                if (open && _selected.isNotEmpty) _selectionBar(r),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ============================================================ dialogs

class _EditEntryDialog extends StatefulWidget {
  final BidEntry entry;

  const _EditEntryDialog({required this.entry});

  @override
  State<_EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<_EditEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _price = TextEditingController(text: widget.entry.pricePerKgGood);
  late final TextEditingController _remarks = TextEditingController(text: widget.entry.remarks ?? '');

  @override
  void dispose() {
    _price.dispose();
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final price = double.tryParse(_price.text) ?? 0;
    return AlertDialog(
      title: Text('Edit ${e.supplierName}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Weights are locked: ${e.goodKg} kg good, ${e.badKg} kg bad.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Price per kg (good) *',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final p = double.tryParse(v ?? '');
                  return (p == null || p <= 0) ? 'Enter a valid price' : null;
                },
              ),
              const SizedBox(height: 6),
              Text('New total: ₱${(e.goodKgNum * price).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _remarks,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Remarks (optional)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.pop(context, {
                'price': double.parse(_price.text),
                'remarks': _remarks.text.trim(),
              });
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _AwardDialog extends StatefulWidget {
  final List<BidEntry> entries;

  const _AwardDialog({required this.entries});

  @override
  State<_AwardDialog> createState() => _AwardDialogState();
}

class _AwardDialogState extends State<_AwardDialog> {
  final _remarks = TextEditingController();

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kg = widget.entries.fold<double>(0, (s, b) => s + b.goodKgNum);
    final total = widget.entries.fold<double>(0, (s, b) => s + b.totalPriceNum);
    return AlertDialog(
      title: const Text('Accept selected entries'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in widget.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${e.supplierName} (${kindLabel(e.gingerKind)}): ${e.goodKg} kg • ₱${e.totalPrice}'),
              ),
            const Divider(height: 20),
            Text('Final: ${kg.toStringAsFixed(2)} kg • ₱${total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'All other pending entries will be rejected and the round will be closed. This cannot be undone.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remarks,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason for choosing (optional)',
                hintText: 'e.g. best quality and price',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _remarks.text.trim()), child: const Text('Accept & close round')),
      ],
    );
  }
}
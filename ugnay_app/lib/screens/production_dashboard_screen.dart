import 'package:flutter/material.dart';

import '../api_client.dart';
import '../production_api.dart';
import 'bidding_round_detail_screen.dart';
import 'home_screen.dart' show logout;
import 'production_widgets.dart';

class ProductionDashboardScreen extends StatefulWidget {
  final String fullName;

  const ProductionDashboardScreen({super.key, required this.fullName});

  @override
  State<ProductionDashboardScreen> createState() => _ProductionDashboardScreenState();
}

class _ProductionDashboardScreenState extends State<ProductionDashboardScreen> {
  late Future<ProductionSummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = getProductionSummary();
  }

  void _reloadSummary() {
    setState(() => _summaryFuture = getProductionSummary());
  }

  Widget _chip(String label, int count, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.shade300),
      ),
      child: Text.rich(TextSpan(
        style: TextStyle(fontSize: 12, color: color.shade900),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(text: '$count', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      )),
    );
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
              const Text('Production'),
              Text('Signed in as ${widget.fullName}', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          actions: [
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _reloadSummary),
            IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout), onPressed: () => logout(context)),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.gavel), text: 'Bidding'),
              Tab(icon: Icon(Icons.groups_outlined), text: 'Suppliers'),
            ],
          ),
        ),
        body: Column(
          children: [
            FutureBuilder<ProductionSummary>(
              future: _summaryFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final s = snapshot.data!;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chip('Open rounds', s.openRounds, Colors.blue),
                        const SizedBox(width: 8),
                        _chip('Awarded', s.awardedRounds, Colors.green),
                        const SizedBox(width: 8),
                        _chip('Suppliers', s.activeSuppliers, Colors.orange),
                      ],
                    ),
                  ),
                );
              },
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _RoundsTab(onChanged: _reloadSummary),
                  _SuppliersTab(onChanged: _reloadSummary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================ Rounds tab

class _RoundsTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _RoundsTab({required this.onChanged});

  @override
  State<_RoundsTab> createState() => _RoundsTabState();
}

class _RoundsTabState extends State<_RoundsTab> {
  String _status = 'OPEN';
  final _search = TextEditingController();
  late Future<List<BiddingRound>> _future;

  static const _statuses = [
    {'value': 'OPEN', 'label': 'Open'},
    {'value': 'AWARDED', 'label': 'Awarded'},
    {'value': 'CANCELLED', 'label': 'Cancelled'},
    {'value': 'ALL', 'label': 'All'},
  ];

  @override
  void initState() {
    super.initState();
    _future = listRounds(status: _status);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = listRounds(status: _status, q: _search.text));
  }

  Future<void> _open(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BiddingRoundDetailScreen(id: id)),
    );
    if (mounted) {
      _reload();
      widget.onChanged();
    }
  }

  Future<void> _newRound() async {
    final data = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _NewRoundDialog(),
    );
    if (data == null) return;
    try {
      final round = await createRound(title: data['title'], notes: data['notes']);
      if (!mounted) return;
      await _open(round.id);
    } on ApiException catch (e) {
      if (mounted) await showMessageDialog(context, 'Could not create round', e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final s in _statuses)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(s['label']!),
                            selected: _status == s['value'],
                            onSelected: (sel) {
                              if (sel && _status != s['value']) {
                                setState(() => _status = s['value']!);
                                _reload();
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _newRound,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New round', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search round #, title, or supplier',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _search.clear();
                        _reload();
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _reload(),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _reload();
              widget.onChanged();
            },
            child: FutureBuilder<List<BiddingRound>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ErrorRetry(message: snapshot.error.toString(), onRetry: _reload);
                }
                final rounds = snapshot.data ?? [];
                if (rounds.isEmpty) {
                  return ListView(children: const [
                    SizedBox(height: 140),
                    Center(child: Text('No bidding rounds here yet.', style: TextStyle(color: Colors.grey))),
                  ]);
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: rounds.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final r = rounds[i];
                    return Card(
                      elevation: 0.8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _open(r.id),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(r.roundNo,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  StatusChip(r.status),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text((r.title != null && r.title!.isNotEmpty) ? r.title! : 'Untitled round',
                                  style: const TextStyle(fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              Text(
                                '${r.biddingDate} • ${r.entryCount} entr${r.entryCount == 1 ? 'y' : 'ies'}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              ),
                              if (r.status == 'AWARDED') ...[
                                const Divider(height: 12, thickness: 0.5),
                                Text(
                                  'Accepted: ${r.acceptedCount} • ₱${r.acceptedTotalPrice}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                              ],
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

class _NewRoundDialog extends StatefulWidget {
  const _NewRoundDialog();

  @override
  State<_NewRoundDialog> createState() => _NewRoundDialogState();
}

class _NewRoundDialogState extends State<_NewRoundDialog> {
  final _title = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New bidding round'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title (optional)',
                hintText: 'e.g. October ginger buying',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'title': _title.text.trim(),
            'notes': _notes.text.trim(),
          }),
          child: const Text('Open round'),
        ),
      ],
    );
  }
}

// ============================================================ Suppliers tab

class _SuppliersTab extends StatefulWidget {
  final VoidCallback onChanged;

  const _SuppliersTab({required this.onChanged});

  @override
  State<_SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends State<_SuppliersTab> {
  final _search = TextEditingController();
  bool _activeOnly = true;
  late Future<List<Supplier>> _future;

  @override
  void initState() {
    super.initState();
    _future = listSuppliers(activeOnly: _activeOnly);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = listSuppliers(activeOnly: _activeOnly, q: _search.text));
  }

  Future<void> _add() async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const SupplierDialog(),
    );
    if (data == null) return;
    try {
      await createSupplier(
        name: data['name'] as String,
        phone: data['phone'] as String,
        address: data['address'] as String,
        notes: data['notes'] as String,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${data['name']} added')));
      _reload();
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) await showMessageDialog(context, 'Could not add supplier', e.message);
    }
  }

  Future<void> _edit(Supplier s) async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => SupplierDialog(supplier: s),
    );
    if (data == null) return;
    try {
      await updateSupplier(
        s.id,
        name: data['name'] as String,
        phone: data['phone'] as String,
        address: data['address'] as String,
        notes: data['notes'] as String,
        isActive: data['is_active'] as bool,
      );
      if (!mounted) return;
      _reload();
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) await showMessageDialog(context, 'Could not update supplier', e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Active only'),
                selected: _activeOnly,
                onSelected: (v) {
                  setState(() => _activeOnly = v);
                  _reload();
                },
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _add,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New supplier', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search suppliers by name',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _search.clear();
                        _reload();
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _reload(),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: FutureBuilder<List<Supplier>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ErrorRetry(message: snapshot.error.toString(), onRetry: _reload);
                }
                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return ListView(children: const [
                    SizedBox(height: 140),
                    Center(child: Text('No suppliers found.', style: TextStyle(color: Colors.grey))),
                  ]);
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = items[i];
                    final details = [
                      if (s.phone != null && s.phone!.isNotEmpty) s.phone!,
                      if (s.address != null && s.address!.isNotEmpty) s.address!,
                    ].join(' • ');
                    return ListTile(
                      leading: CircleAvatar(child: Text(s.name.isNotEmpty ? s.name[0].toUpperCase() : '?')),
                      title: Text(s.name),
                      subtitle: details.isEmpty ? null : Text(details),
                      trailing: s.isActive
                          ? const Icon(Icons.edit_outlined, size: 18)
                          : const Text('Inactive', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      onTap: () => _edit(s),
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
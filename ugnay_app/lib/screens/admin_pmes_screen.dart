import 'package:flutter/material.dart';

import '../admin_pmes_api.dart';
import 'admin_pmes_detail_screen.dart';

class AdminPmesScreen extends StatefulWidget {
  const AdminPmesScreen({super.key});

  @override
  State<AdminPmesScreen> createState() => _AdminPmesScreenState();
}

class _AdminPmesScreenState extends State<AdminPmesScreen> {
  static const _statuses = ['SUBMITTED', 'APPROVED', 'REJECTED'];
  String _status = 'SUBMITTED';
  late Future<List<AdminPmesSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = listAdminPmes(_status);
  }

  void _select(String status) {
    setState(() {
      _status = status;
      _future = listAdminPmes(status);
    });
  }

  Future<void> _reload() async {
    final f = listAdminPmes(_status);
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  Future<void> _open(AdminPmesSummary a) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminPmesDetailScreen(id: a.id)),
    );
    if (mounted) _reload();
  }

  String _date(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(
            spacing: 8,
            children: [
              for (final s in _statuses)
                ChoiceChip(
                  label: Text(s),
                  selected: _status == s,
                  onSelected: (_) => _select(s),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AdminPmesSummary>>(
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
              final items = snapshot.data!;
              return RefreshIndicator(
                onRefresh: _reload,
                child: items.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 160),
                          Center(child: Text('No ${_status.toLowerCase()} PMES applications')),
                        ],
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final a = items[i];
                          final name = (a.fullName == null || a.fullName!.isEmpty)
                              ? a.email
                              : a.fullName!;
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.school_outlined)),
                            title: Text(name),
                            subtitle: Text(
                              '${a.referenceNo ?? 'No reference'} · ${_date(a.scheduleDate)} · ${a.status}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(a),
                          );
                        },
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

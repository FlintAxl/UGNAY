import 'package:flutter/material.dart';

import '../api_client.dart';
import 'applicant_detail_screen.dart';
import 'home_screen.dart' show logout;

class AdminDashboardScreen extends StatelessWidget {
  final String fullName;

  const AdminDashboardScreen({super.key, required this.fullName});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Applicants'),
              Text('Signed in as $fullName', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout),
              onPressed: () => logout(context),
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'Pending'), Tab(text: 'Active'), Tab(text: 'Rejected')],
          ),
        ),
        body: const TabBarView(
          children: [
            _ApplicantList(status: 'PENDING'),
            _ApplicantList(status: 'ACTIVE'),
            _ApplicantList(status: 'REJECTED'),
          ],
        ),
      ),
    );
  }
}

class _ApplicantList extends StatefulWidget {
  final String status;

  const _ApplicantList({required this.status});

  @override
  State<_ApplicantList> createState() => _ApplicantListState();
}

class _ApplicantListState extends State<_ApplicantList> {
  late Future<List<Applicant>> _future;

  @override
  void initState() {
    super.initState();
    _future = listApplicants(widget.status);
  }

  Future<void> _reload() async {
    final f = listApplicants(widget.status);
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  Future<void> _open(Applicant a) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ApplicantDetailScreen(id: a.id)),
    );
    if (mounted) _reload();
  }

  String _date(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Applicant>>(
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
                    Center(child: Text('No ${widget.status.toLowerCase()} applicants')),
                  ],
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final a = items[i];
                    final subtitle = widget.status == 'ACTIVE'
                        ? '${a.role} · ${a.email}'
                        : '${a.email} · applied ${_date(a.createdAt)}';
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(a.fullName.isNotEmpty ? a.fullName[0].toUpperCase() : '?'),
                      ),
                      title: Text(a.fullName),
                      subtitle: Text(subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(a),
                    );
                  },
                ),
        );
      },
    );
  }
}
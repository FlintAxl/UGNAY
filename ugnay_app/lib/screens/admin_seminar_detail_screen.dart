import 'package:flutter/material.dart';

import '../seminar_api.dart';

class AdminSeminarDetailScreen extends StatefulWidget {
  final String seminarId;

  const AdminSeminarDetailScreen({super.key, required this.seminarId});

  @override
  State<AdminSeminarDetailScreen> createState() =>
      _AdminSeminarDetailScreenState();
}

class _AdminSeminarDetailScreenState extends State<AdminSeminarDetailScreen> {
  late Future<SeminarAttendance> _future;

  @override
  void initState() {
    super.initState();
    _future = getSeminarAttendance(widget.seminarId);
  }

  void _retry() =>
      setState(() => _future = getSeminarAttendance(widget.seminarId));

  Future<void> _reload() async {
    final f = getSeminarAttendance(widget.seminarId);
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  String _dateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final value = DateTime.tryParse(iso);
    if (value == null) return iso;
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _statCard(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _headerCard(SeminarAttendance data) {
    final seminar = data.seminar;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(seminar.label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(seminar.venue),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(seminar.phase)),
                Chip(label: Text('Total ${data.totals.total}')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _statCard('Attending', data.totals.attending, Colors.green),
                const SizedBox(width: 8),
                _statCard("Can't attend", data.totals.notAttending, Colors.red),
                const SizedBox(width: 8),
                _statCard('No response', data.totals.noResponse, Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, Color color, List<SeminarParticipant> members) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(Icons.people_outline, color: color),
            ),
            title: Text(title),
            trailing: Chip(label: Text('${members.length}')),
          ),
          const Divider(height: 1),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No members in this group.'),
            )
          else
            for (final member in members)
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    member.fullName.isNotEmpty
                        ? member.fullName[0].toUpperCase()
                        : '?',
                  ),
                ),
                title: Text(
                  member.fullName.isEmpty ? member.email : member.fullName,
                ),
                subtitle: Text(
                  [
                    member.email,
                    member.phone,
                    if (member.respondedAt != null)
                      'Responded ${_dateTime(member.respondedAt)}',
                  ].where((value) => value.isNotEmpty).join(' · '),
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PMES seminar attendance')),
      body: SafeArea(
        child: FutureBuilder<SeminarAttendance>(
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
                      Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _retry,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final data = snapshot.data!;
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _headerCard(data),
                  _section(
                    'Available (Attending)',
                    Colors.green,
                    data.attending,
                  ),
                  _section(
                    "Not Available (Can't Attend)",
                    Colors.red,
                    data.notAttending,
                  ),
                  _section('No Response', Colors.orange, data.noResponse),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

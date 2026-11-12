import 'package:flutter/material.dart';

import '../api_client.dart';
import '../seminar_api.dart';
import 'admin_seminar_detail_screen.dart';

class AdminSeminarScreen extends StatefulWidget {
  const AdminSeminarScreen({super.key});

  @override
  State<AdminSeminarScreen> createState() => _AdminSeminarScreenState();
}

class _SeminarData {
  final List<PmesPreferenceDate> preferences;
  final List<PmesSeminarSummary> seminars;

  const _SeminarData(this.preferences, this.seminars);
}

class _AdminSeminarScreenState extends State<AdminSeminarScreen> {
  late Future<_SeminarData> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SeminarData> _load() async {
    final preferences = await listPmesPreferences();
    final seminars = await listSeminars();
    return _SeminarData(preferences, seminars);
  }

  Future<void> _reload() async {
    final f = _load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  PmesSeminarSummary? _upcoming(List<PmesSeminarSummary> seminars) {
    for (final s in seminars) {
      if (s.status == 'SCHEDULED' && s.phase == 'UPCOMING') return s;
    }
    return null;
  }

  PmesPreferenceDate? _bestPreference(List<PmesPreferenceDate> prefs) {
    for (final pref in prefs) {
      if (pref.isMostPreferred && !pref.isPast) return pref;
    }
    for (final pref in prefs) {
      if (!pref.isPast) return pref;
    }
    return null;
  }

  Future<void> _message(String title, String text) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _schedule(PmesPreferenceDate pref) =>
      _scheduleDate(pref.date, pref.label, pref.count);

  Future<void> _scheduleDate(String date, String label, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Schedule PMES seminar'),
        content: Text(
          'Schedule the PMES seminar on $label?\n\n'
          '$count applicant(s) preferred this date.\n\n'
          'All active associate members will be invited.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Schedule'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await scheduleSeminar(date);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PMES seminar scheduled.')));
      await _reload();
    } on ApiException catch (e) {
      if (mounted) await _message('Could not schedule', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scheduleAnother(
    List<PmesPreferenceDate> prefs,
    PmesSeminarSummary? upcoming,
  ) async {
    if (upcoming != null || _busy) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: 'Choose a Saturday',
      selectableDayPredicate: (day) => day.weekday == DateTime.saturday,
    );
    if (picked == null || !mounted) return;

    final date = _isoDate(picked);
    PmesPreferenceDate? match;
    for (final p in prefs) {
      if (p.date == date) {
        match = p;
        break;
      }
    }
    await _scheduleDate(
      date,
      match?.label ?? _label(picked),
      match?.count ?? 0,
    );
  }

  Future<void> _cancel(PmesSeminarSummary seminar) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelSeminarDialog(dateLabel: seminar.label),
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await cancelSeminar(seminar.id, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PMES seminar cancelled.')));
      await _reload();
    } on ApiException catch (e) {
      if (mounted) await _message('Could not cancel', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAttendance(PmesSeminarSummary seminar) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminSeminarDetailScreen(seminarId: seminar.id),
      ),
    );
    if (mounted) _reload();
  }

  void _showApplicants(PmesPreferenceDate pref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(pref.label, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('${pref.count} applicant(s)'),
          const SizedBox(height: 12),
          if (pref.applicants.isEmpty)
            const Text('No applicants chose this date.')
          else
            for (final a in pref.applicants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(
                    a.fullName.isNotEmpty ? a.fullName[0].toUpperCase() : '?',
                  ),
                ),
                title: Text(a.fullName.isEmpty ? a.email : a.fullName),
                subtitle: Text(
                  [
                    a.email,
                    a.referenceNo ?? '',
                    a.status,
                  ].where((value) => value.isNotEmpty).join(' · '),
                ),
              ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _upcomingCard(PmesSeminarSummary seminar) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_available, color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Upcoming PMES seminar',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(seminar.label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(seminar.venue),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Attending ${seminar.attending}')),
                Chip(label: Text("Can't attend ${seminar.notAttending}")),
                Chip(label: Text('No response ${seminar.noResponse}')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _cancel(seminar),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel seminar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _openAttendance(seminar),
                    icon: const Icon(Icons.people_outline),
                    label: const Text('View attendance'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _preferencesTable(
    List<PmesPreferenceDate> prefs,
    PmesSeminarSummary? upcoming,
  ) {
    if (prefs.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No applicant preferences yet.'),
        ),
      );
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 20,
          horizontalMargin: 12,
          columns: const [
            DataColumn(label: Text('Saturday')),
            DataColumn(label: Text('Applicants'), numeric: true),
            DataColumn(label: Text('Preference')),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final pref in prefs)
              DataRow(
                cells: [
                  DataCell(Text(pref.label)),
                  DataCell(Text('${pref.count}')),
                  DataCell(
                    pref.isMostPreferred
                        ? const Chip(label: Text('Most preferred'))
                        : const Text('—'),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _showApplicants(pref),
                          child: const Text('View'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton.tonal(
                          onPressed: (pref.isPast || upcoming != null || _busy)
                              ? null
                              : () => _schedule(pref),
                          child: Text(pref.isPast ? 'Past' : 'Schedule'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _seminarCard(PmesSeminarSummary seminar) {
    final color = switch (seminar.phase) {
      'UPCOMING' => Colors.blue,
      'PAST' => Colors.blueGrey,
      _ => Colors.red,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(Icons.event, color: color),
        ),
        title: Text(seminar.label),
        subtitle: Text(
          '${seminar.phase} · ${seminar.venue}\n'
          'Attending ${seminar.attending} · '
          "Can't attend ${seminar.notAttending} · "
          'No response ${seminar.noResponse}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (seminar.phase == 'UPCOMING')
              IconButton(
                tooltip: 'Cancel seminar',
                icon: const Icon(Icons.cancel_outlined),
                onPressed: _busy ? null : () => _cancel(seminar),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _openAttendance(seminar),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SeminarData>(
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

        final data = snapshot.data!;
        final upcoming = _upcoming(data.seminars);
        final best = _bestPreference(data.preferences);
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (upcoming != null) _upcomingCard(upcoming),
              _sectionTitle('Applicant preferences'),
              if (best != null) ...[
                FilledButton.icon(
                  onPressed: (upcoming == null && !_busy)
                      ? () => _schedule(best)
                      : null,
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Schedule most preferred Saturday'),
                ),
                const SizedBox(height: 8),
              ],
              _preferencesTable(data.preferences, upcoming),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: (upcoming == null && !_busy)
                    ? () => _scheduleAnother(data.preferences, upcoming)
                    : null,
                icon: const Icon(Icons.calendar_month),
                label: const Text('Schedule another Saturday'),
              ),
              const SizedBox(height: 20),
              _sectionTitle('Scheduled seminars'),
              if (data.seminars.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No seminars scheduled yet.'),
                )
              else
                for (final seminar in data.seminars) _seminarCard(seminar),
            ],
          ),
        );
      },
    );
  }
}

class _CancelSeminarDialog extends StatefulWidget {
  final String dateLabel;

  const _CancelSeminarDialog({required this.dateLabel});

  @override
  State<_CancelSeminarDialog> createState() => _CancelSeminarDialogState();
}

class _CancelSeminarDialogState extends State<_CancelSeminarDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel PMES seminar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cancel the seminar on ${widget.dateLabel}? '
            'Members will no longer see it.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep seminar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _reason.text.trim()),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Cancel seminar'),
        ),
      ],
    );
  }
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _label(DateTime value) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final day = value.day.toString().padLeft(2, '0');
  return '${weekdays[value.weekday - 1]}, '
      '${months[value.month - 1]} $day, ${value.year}';
}

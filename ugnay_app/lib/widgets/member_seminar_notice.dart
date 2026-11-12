import 'package:flutter/material.dart';

import '../api_client.dart';
import '../seminar_api.dart';

/// In-app notice shown to active associate members on their landing page.
class MemberSeminarNotice extends StatefulWidget {
  const MemberSeminarNotice({super.key});

  @override
  State<MemberSeminarNotice> createState() => _MemberSeminarNoticeState();
}

class _MemberSeminarNoticeState extends State<MemberSeminarNotice> {
  MemberSeminar? _data;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await getMemberSeminar();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _respond(String response) async {
    final seminar = _data?.seminar;
    if (seminar == null || _busy) return;

    setState(() => _busy = true);
    try {
      final data = await respondToSeminar(seminar.id, response);
      if (!mounted) return;
      setState(() => _data = data);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response == 'ATTEND'
                ? 'Marked as attending.'
                : "Marked as can't attend.",
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _responseLabel(String? response) => switch (response) {
    'ATTEND' => 'You chose: Attend',
    'DECLINE' => "You chose: Can't Attend",
    _ => 'No response yet',
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        margin: EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading seminar notice...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_error!),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final seminar = _data?.seminar;
    if (seminar == null) return const SizedBox.shrink();

    final response = _data?.response;
    final canRespond = _data?.canRespond ?? seminar.canRespond;
    final responseColor = switch (response) {
      'ATTEND' => Colors.green,
      'DECLINE' => Colors.red,
      _ => Colors.blueGrey,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.school_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PMES Seminar Notice',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _busy ? null : _load,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(seminar.label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Venue: ${seminar.venue}'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(_responseLabel(response)),
                backgroundColor: responseColor.withValues(alpha: 0.15),
                side: BorderSide(color: responseColor.withValues(alpha: 0.5)),
              ),
            ),
            if (!canRespond)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Response locked — the seminar date has passed.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (!canRespond || _busy)
                        ? null
                        : () => _respond('ATTEND'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Attend'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (!canRespond || _busy)
                        ? null
                        : () => _respond('DECLINE'),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text("Can't Attend"),
                  ),
                ),
              ],
            ),
            if (canRespond)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'You can change your response until the seminar date.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

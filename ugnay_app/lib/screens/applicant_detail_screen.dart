import 'package:flutter/material.dart';

import '../api_client.dart';

const _assignableRoles = ['logistics', 'production', 'marketing', 'microfinance', 'savings'];

class ApplicantDetailScreen extends StatefulWidget {
  final String id;

  const ApplicantDetailScreen({super.key, required this.id});

  @override
  State<ApplicantDetailScreen> createState() => _ApplicantDetailScreenState();
}

class _ApplicantDetailScreenState extends State<ApplicantDetailScreen> {
  late Future<Applicant> _future;
  String? _role;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = getApplicant(widget.id);
  }

  void _retry() => setState(() => _future = getApplicant(widget.id));

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

  Future<void> _approve(Applicant a) async {
    final role = _role;
    if (role == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a role first.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve applicant'),
        content: Text('Approve ${a.fullName} as $role?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await approveApplicant(a.id, role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${a.fullName} approved as $role')),
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) await _message('Could not approve', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(Applicant a) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectDialog(),
    );
    if (reason == null) return;

    setState(() => _busy = true);
    try {
      await rejectApplicant(a.id, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${a.fullName} rejected')),
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) await _message('Could not reject', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _zoom(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(child: Image.network(url)),
      ),
    );
  }

  Widget _photo(String label, String? url) {
    final theme = Theme.of(context);
    Widget content;
    if (url == null) {
      content = const Center(child: Text('No photo'));
    } else {
      content = Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, error, stack) => const Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Text('Could not load photo', textAlign: TextAlign.center),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 3 / 4,
          child: InkWell(
            onTap: url == null ? null : () => _zoom(url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: content),
            ),
          ),
        ),
      ],
    );
  }

  Widget _info(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Applicant')),
      body: SafeArea(
        child: FutureBuilder<Applicant>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(snapshot.error.toString()),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              );
            }
            final a = snapshot.data!;
            final applied = a.createdAt.length >= 10 ? a.createdAt.substring(0, 10) : a.createdAt;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _photo('ID photo', a.idPhotoUrl)),
                    const SizedBox(width: 12),
                    Expanded(child: _photo('Face photo', a.facePhotoUrl)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(a.fullName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(label: Text(a.status)),
                    if (a.role != 'UNASSIGNED') Chip(label: Text(a.role)),
                  ],
                ),
                const SizedBox(height: 8),
                _info(Icons.email_outlined, a.email),
                _info(Icons.phone_outlined, a.phone),
                _info(Icons.home_outlined, (a.address == null || a.address!.isEmpty) ? '—' : a.address!),
                _info(Icons.event_outlined, 'Applied $applied'),
                if (a.status == 'REJECTED')
                  _info(Icons.info_outline, 'Rejected: ${a.rejectionReason ?? 'No reason given'}'),
                if (a.status == 'PENDING') ...[
                  const SizedBox(height: 20),
                  DropdownMenu<String>(
                    label: const Text('Assign role'),
                    expandedInsets: EdgeInsets.zero,
                    enabled: !_busy,
                    dropdownMenuEntries: [
                      for (final r in _assignableRoles) DropdownMenuEntry(value: r, label: r),
                    ],
                    onSelected: (v) => setState(() => _role = v),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _approve(a),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _reject(a),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject applicant'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _reason,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason (shown to the applicant)',
            border: OutlineInputBorder(),
          ),
          validator: (v) =>
              (v == null || v.trim().length < 3) ? 'Enter a reason (min 3 characters)' : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _reason.text.trim());
            }
          },
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
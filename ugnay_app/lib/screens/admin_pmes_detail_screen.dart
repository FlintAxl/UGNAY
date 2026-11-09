import 'package:flutter/material.dart';

import '../admin_pmes_api.dart';
import '../api_client.dart';
import '../pmes_api.dart';
import 'applicant_detail_screen.dart';

class AdminPmesDetailScreen extends StatefulWidget {
  final String id;

  const AdminPmesDetailScreen({super.key, required this.id});

  @override
  State<AdminPmesDetailScreen> createState() => _AdminPmesDetailScreenState();
}

class _AdminPmesDetailScreenState extends State<AdminPmesDetailScreen> {
  late Future<AdminPmesDetail> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = getAdminPmes(widget.id);
  }

  void _retry() => setState(() => _future = getAdminPmes(widget.id));

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

  Future<void> _approve(PmesApplication a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve PMES application'),
        content: Text(
          'Approve ${a.referenceNo ?? 'this application'}? The applicant account is still approved separately.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await approveAdminPmes(widget.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PMES application approved.')),
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) await _message('Could not approve', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(PmesApplication a) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _PmesRejectDialog(),
    );
    if (reason == null) return;

    setState(() => _busy = true);
    try {
      await rejectAdminPmes(widget.id, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PMES application rejected.')),
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) await _message('Could not reject', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _v(String? value) =>
      (value == null || value.trim().isEmpty) ? '—' : value.trim();

  String _date(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }

  Widget _card(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );

  Widget _kv(String label, String? value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(label, style: Theme.of(context).textTheme.labelMedium),
            ),
            Expanded(child: Text(_v(value))),
          ],
        ),
      );

  Widget _statusChip(String status) {
    final color = switch (status) {
      'APPROVED' => Colors.green,
      'REJECTED' => Colors.red,
      _ => Colors.blueGrey,
    };
    return Chip(
      label: Text(status),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );
  }

  Widget _beneficiaries(PmesApplication a) {
    if (a.beneficiaries.isEmpty) return const Text('None listed');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < a.beneficiaries.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${i + 1}. ${_v(a.beneficiaries[i].name)} · '
              '${_v(a.beneficiaries[i].relationship)} · '
              '${_date(a.beneficiaries[i].birthDate)}',
            ),
          ),
      ],
    );
  }

  Widget _education(PmesApplication a) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('Kolehiyo', '${_v(a.education.college.school)} (${_v(a.education.college.yearGraduated)})'),
          _kv('Bokasyonal', '${_v(a.education.vocational.school)} (${_v(a.education.vocational.yearGraduated)})'),
          _kv('Sekondarya', '${_v(a.education.secondary.school)} (${_v(a.education.secondary.yearGraduated)})'),
          _kv('Elementarya', '${_v(a.education.elementary.school)} (${_v(a.education.elementary.yearGraduated)})'),
        ],
      );

  Widget _actions(PmesApplication a) {
    if (a.status != 'SUBMITTED') return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Approving PMES does not activate the account. Approve the applicant account separately.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : () => _approve(a),
              icon: const Icon(Icons.check),
              label: const Text('Approve PMES'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _reject(a),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.close),
              label: const Text('Reject PMES'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PMES application')),
      body: SafeArea(
        child: FutureBuilder<AdminPmesDetail>(
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
                    Text(snapshot.error.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              );
            }
            final detail = snapshot.data!;
            final a = detail.application;
            final applicant = detail.applicant;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _card('Application', [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _statusChip(a.status ?? 'SUBMITTED'),
                      Chip(label: Text(a.referenceNo ?? 'No reference')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _kv('Schedule', a.scheduleDate),
                  _kv('Venue', a.venue),
                  _kv('Submitted', _date(a.createdAt)),
                  if ((a.rejectionReason ?? '').isNotEmpty)
                    _kv('Rejection reason', a.rejectionReason),
                ]),
                _card('Applicant account', [
                  _kv('Name', applicant?.fullName),
                  _kv('Email', applicant?.email),
                  _kv('Phone', applicant?.phone),
                  _kv('Account status', applicant?.status),
                  _kv('Role', applicant?.role),
                  _kv(
                    'Membership',
                    applicant?.membershipType == 'ASSOCIATE'
                        ? 'Associate member'
                        : applicant?.membershipType == 'FULLY_PLEDGED'
                            ? 'Fully pledged member'
                            : 'Not set',
                  ),
                  if (applicant != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ApplicantDetailScreen(id: applicant.id),
                        ),
                      ),
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Open applicant account'),
                    ),
                  ],
                ]),
                _actions(a),
                _card('Personal na Impormasyon', [
                  _kv('Uri ng Miyembro', a.membershipCategory),
                  _kv('Apelyido', a.lastName),
                  _kv('Pangalan', a.firstName),
                  _kv('Panggitnang Pangalan', a.middleName),
                  _kv('Tirahan', a.address),
                  _kv('Kapanganakan', _date(a.birthDate)),
                  _kv('Lugar ng Kapanganakan', a.birthPlace),
                  _kv('Civil Status', a.civilStatus),
                  _kv('Kasarian', a.sex),
                  _kv('Nasyonalidad', a.nationality),
                  _kv('Telepono', a.phone),
                  _kv('Relihiyon', a.religion),
                  _kv('Timbang', a.weight),
                  _kv('Taas', a.height),
                  _kv('Trabaho', a.occupation),
                ]),
                _card('Pamilya', [
                  _kv('Ina', a.motherName),
                  _kv('Trabaho ng Ina', a.motherOccupation),
                  _kv('Ama', a.fatherName),
                  _kv('Trabaho ng Ama', a.fatherOccupation),
                  _kv('Asawa', a.spouseName),
                  _kv('Trabaho ng Asawa', a.spouseOccupation),
                ]),
                _card('Mga Benepisyaryo', [_beneficiaries(a)]),
                _card('Pinag-aralan at Paaralan', [_education(a)]),
                _card('Pagkakakilanlan', [
                  _kv('TIN', a.ids.tin),
                  _kv('PAG-IBIG #', a.ids.pagibig),
                  _kv('SSS #', a.ids.sss),
                  _kv('PHILHEALTH #', a.ids.philhealth),
                  _kv('SENIOR ID #', a.ids.seniorId),
                  _kv('NATIONAL ID', a.ids.nationalId),
                  _kv("IBA PA", a.ids.other),
                ]),
                _card('Pirma', [
                  _kv('Pangalan at Pirma', a.signatureName),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PmesRejectDialog extends StatefulWidget {
  const _PmesRejectDialog();

  @override
  State<_PmesRejectDialog> createState() => _PmesRejectDialogState();
}

class _PmesRejectDialogState extends State<_PmesRejectDialog> {
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
      title: const Text('Reject PMES application'),
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

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../api_client.dart';
import '../pmes_api.dart';
import '../pmes_pdf.dart';

const _venue = 'PRIC Cooperative, Barangay Pinagdanlayan, Dolores, Quezon';

class PmesApplicationScreen extends StatefulWidget {
  final String pmesToken;
  final String email;

  const PmesApplicationScreen({
    super.key,
    required this.pmesToken,
    this.email = '',
  });

  @override
  State<PmesApplicationScreen> createState() => _PmesApplicationScreenState();
}

class _PmesApplicationScreenState extends State<PmesApplicationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _lastName = TextEditingController();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _address = TextEditingController();
  final _birthDate = TextEditingController();
  final _birthPlace = TextEditingController();
  final _religion = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _nationality = TextEditingController(text: 'Filipino');
  final _phone = TextEditingController();
  final _occupation = TextEditingController();

  final _motherName = TextEditingController();
  final _motherOccupation = TextEditingController();
  final _fatherName = TextEditingController();
  final _fatherOccupation = TextEditingController();
  final _spouseName = TextEditingController();
  final _spouseOccupation = TextEditingController();

  final _collegeSchool = TextEditingController();
  final _collegeYear = TextEditingController();
  final _vocationalSchool = TextEditingController();
  final _vocationalYear = TextEditingController();
  final _secondarySchool = TextEditingController();
  final _secondaryYear = TextEditingController();
  final _elementarySchool = TextEditingController();
  final _elementaryYear = TextEditingController();

  final _tin = TextEditingController();
  final _pagibig = TextEditingController();
  final _sss = TextEditingController();
  final _philhealth = TextEditingController();
  final _seniorId = TextEditingController();
  final _nationalId = TextEditingController();
  final _otherId = TextEditingController();

  final _signatureName = TextEditingController();

  final _beneficiaryName = List.generate(3, (_) => TextEditingController());
  final _beneficiaryRelation = List.generate(3, (_) => TextEditingController());
  final _beneficiaryBirthDate = List.generate(3, (_) => TextEditingController());
  final _beneficiaryDateValue = List<DateTime?>.filled(3, null);

  DateTime? _birthDateValue;
  String? _category;
  String? _civilStatus;
  String? _sex;
  String? _scheduleDate;

  List<PmesScheduleOption> _options = [];
  PmesApplication? _saved;
  bool _loading = true;
  bool _busy = false;
  bool _schedulePassed = false;

  String get _status => _saved?.status ?? 'SUBMITTED';
  bool get _approved => _status == 'APPROVED';
  bool get _rejected => _status == 'REJECTED';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _lastName, _firstName, _middleName, _address, _birthDate, _birthPlace,
      _religion, _weight, _height, _nationality, _phone, _occupation,
      _motherName, _motherOccupation, _fatherName, _fatherOccupation,
      _spouseName, _spouseOccupation,
      _collegeSchool, _collegeYear, _vocationalSchool, _vocationalYear,
      _secondarySchool, _secondaryYear, _elementarySchool, _elementaryYear,
      _tin, _pagibig, _sss, _philhealth, _seniorId, _nationalId, _otherId,
      _signatureName,
      ..._beneficiaryName, ..._beneficiaryRelation, ..._beneficiaryBirthDate,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final options = await getPmesScheduleOptions(widget.pmesToken, count: 52);
      final app = await getPmesApplication(widget.pmesToken);
      if (!mounted) return;
      setState(() {
        _options = options;
        _saved = app;
        if (app != null) _fill(app);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e.message);
    }
  }

  void _fill(PmesApplication app) {
    _lastName.text = app.lastName;
    _firstName.text = app.firstName;
    _middleName.text = app.middleName;
    _address.text = app.address;
    _birthPlace.text = app.birthPlace;
    final bd = DateTime.tryParse(app.birthDate);
    _birthDateValue = bd;
    _birthDate.text = bd == null ? '' : _iso(bd);
    _religion.text = app.religion;
    _weight.text = app.weight;
    _height.text = app.height;
    _nationality.text = app.nationality.isEmpty ? 'Filipino' : app.nationality;
    _phone.text = app.phone;
    _occupation.text = app.occupation;

    _motherName.text = app.motherName;
    _motherOccupation.text = app.motherOccupation;
    _fatherName.text = app.fatherName;
    _fatherOccupation.text = app.fatherOccupation;
    _spouseName.text = app.spouseName;
    _spouseOccupation.text = app.spouseOccupation;

    for (var i = 0; i < 3 && i < app.beneficiaries.length; i++) {
      final b = app.beneficiaries[i];
      _beneficiaryName[i].text = b.name;
      _beneficiaryRelation[i].text = b.relationship;
      final d = DateTime.tryParse(b.birthDate);
      _beneficiaryDateValue[i] = d;
      _beneficiaryBirthDate[i].text = d == null ? '' : _iso(d);
    }

    final e = app.education;
    _collegeSchool.text = e.college.school;
    _collegeYear.text = e.college.yearGraduated;
    _vocationalSchool.text = e.vocational.school;
    _vocationalYear.text = e.vocational.yearGraduated;
    _secondarySchool.text = e.secondary.school;
    _secondaryYear.text = e.secondary.yearGraduated;
    _elementarySchool.text = e.elementary.school;
    _elementaryYear.text = e.elementary.yearGraduated;

    _tin.text = app.ids.tin;
    _pagibig.text = app.ids.pagibig;
    _sss.text = app.ids.sss;
    _philhealth.text = app.ids.philhealth;
    _seniorId.text = app.ids.seniorId;
    _nationalId.text = app.ids.nationalId;
    _otherId.text = app.ids.other;

    _signatureName.text = app.signatureName;
    _category = app.membershipCategory.isEmpty ? null : app.membershipCategory;
    _civilStatus = app.civilStatus.isEmpty ? null : app.civilStatus;
    _sex = app.sex.isEmpty ? null : app.sex;
    _scheduleDate = app.scheduleDate.isEmpty ? null : app.scheduleDate;

    if (app.scheduleDate.isNotEmpty &&
        !_options.any((o) => o.date == app.scheduleDate)) {
      _options = [
        PmesScheduleOption(
          date: app.scheduleDate,
          label: app.scheduleDate,
          venue: app.venue,
        ),
        ..._options,
      ];
    }

    final scheduled = DateTime.tryParse(app.scheduleDate);
    if (scheduled != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      _schedulePassed = scheduled.isBefore(today);
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDateValue ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDateValue = picked;
        _birthDate.text = _iso(picked);
      });
    }
  }

  Future<void> _pickBeneficiaryDate(int index) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _beneficiaryDateValue[index] ?? DateTime(now.year - 10, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _beneficiaryDateValue[index] = picked;
        _beneficiaryBirthDate[index].text = _iso(picked);
      });
    }
  }

  PmesApplication _fromForm() => PmesApplication(
        membershipCategory: _category ?? '',
        lastName: _lastName.text.trim(),
        firstName: _firstName.text.trim(),
        middleName: _middleName.text.trim(),
        address: _address.text.trim(),
        birthDate: _birthDate.text.trim(),
        birthPlace: _birthPlace.text.trim(),
        civilStatus: _civilStatus ?? '',
        sex: _sex ?? '',
        nationality: _nationality.text.trim(),
        phone: _phone.text.trim(),
        religion: _religion.text.trim(),
        weight: _weight.text.trim(),
        height: _height.text.trim(),
        occupation: _occupation.text.trim(),
        motherName: _motherName.text.trim(),
        motherOccupation: _motherOccupation.text.trim(),
        fatherName: _fatherName.text.trim(),
        fatherOccupation: _fatherOccupation.text.trim(),
        spouseName: _spouseName.text.trim(),
        spouseOccupation: _spouseOccupation.text.trim(),
        beneficiaries: [
          for (var i = 0; i < 3; i++)
            PmesBeneficiary(
              name: _beneficiaryName[i].text.trim(),
              relationship: _beneficiaryRelation[i].text.trim(),
              birthDate: _beneficiaryBirthDate[i].text.trim(),
            ),
        ],
        education: PmesEducation(
          college: PmesEducationEntry(
            school: _collegeSchool.text.trim(),
            yearGraduated: _collegeYear.text.trim(),
          ),
          vocational: PmesEducationEntry(
            school: _vocationalSchool.text.trim(),
            yearGraduated: _vocationalYear.text.trim(),
          ),
          secondary: PmesEducationEntry(
            school: _secondarySchool.text.trim(),
            yearGraduated: _secondaryYear.text.trim(),
          ),
          elementary: PmesEducationEntry(
            school: _elementarySchool.text.trim(),
            yearGraduated: _elementaryYear.text.trim(),
          ),
        ),
        ids: PmesIds(
          tin: _tin.text.trim(),
          pagibig: _pagibig.text.trim(),
          sss: _sss.text.trim(),
          philhealth: _philhealth.text.trim(),
          seniorId: _seniorId.text.trim(),
          nationalId: _nationalId.text.trim(),
          other: _otherId.text.trim(),
        ),
        scheduleDate: _scheduleDate ?? '',
        venue: _venue,
        signatureName: _signatureName.text.trim(),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_scheduleDate == null || _scheduleDate!.isEmpty) {
      _showError('Please choose a PMES schedule.');
      return;
    }
    final resubmitting = _rejected;
    setState(() => _busy = true);
    try {
      final saved = await savePmesApplication(widget.pmesToken, _fromForm());
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _schedulePassed = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resubmitting
                ? 'PMES application resubmitted for review. You can still print or save the PDF.'
                : 'PMES application saved. You can now print or save the PDF.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final app = _saved;
    if (app == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await buildPmesPdf(app);
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: 'PMES-${app.referenceNo ?? 'application'}.pdf',
      );
    } catch (e) {
      _showError('Could not prepare the PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final app = _saved;
    if (app == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await buildPmesPdf(app);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'PMES-${app.referenceNo ?? 'application'}.pdf',
      );
    } catch (e) {
      _showError('Could not prepare the PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- widgets

  Widget _card(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  Widget _tf(
    TextEditingController controller,
    String label, {
    bool required = false,
    TextInputType? keyboard,
    int maxLines = 1,
    String? hint,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboard,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
        ),
      );

  Widget _dropdown({
    required String label,
    required String? value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
    bool required = false,
    bool enabled = true,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          items: items.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: enabled ? onChanged : null,
          validator: required
              ? (v) => v == null ? 'Required' : null
              : null,
        ),
      );

  Widget _dateField(
    TextEditingController controller,
    String label,
    VoidCallback onTap, {
    bool required = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          readOnly: true,
          onTap: onTap,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
        ),
      );

  Widget _row(List<Widget> children) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: children[i]),
          ],
        ],
      );

  Widget _educationRow(
    String label,
    TextEditingController school,
    TextEditingController year,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: school,
                decoration: InputDecoration(
                  labelText: '$label (Paaralan)',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: TextFormField(
                controller: year,
                decoration: const InputDecoration(
                  labelText: 'Taon',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _beneficiarySection(int index) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Benepisyaryo ${index + 1}',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            _tf(_beneficiaryName[index], 'Pangalan'),
            _row([
              _tf(_beneficiaryRelation[index], 'Kaugnayan'),
              _dateField(
                _beneficiaryBirthDate[index],
                'Kapanganakan',
                () => _pickBeneficiaryDate(index),
              ),
            ]),
          ],
        ),
      );

  Widget _statusCard() {
    final scheme = Theme.of(context).colorScheme;
    final (background, message) = switch (_status) {
      'APPROVED' => (
          scheme.secondaryContainer,
          'Your PMES application has been approved. Your answers are now locked.',
        ),
      'REJECTED' => (
          scheme.errorContainer,
          'Your PMES application was rejected. You can edit your answers and resubmit below.',
        ),
      _ => (
          scheme.surfaceContainerHighest,
          'Your PMES application has been submitted and is waiting for admin review.',
        ),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: $_status',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message),
            if (_rejected && (_saved?.rejectionReason ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Reason: ${_saved!.rejectionReason}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scheduleCard() {
    final items = {for (final o in _options) o.date: o.label};
    return _card('PMES Schedule', [
      if (_schedulePassed)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Your chosen PMES schedule has passed. You can still print or save your PDF, but the answers can no longer be edited.',
          ),
        ),
      if (_options.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('No PMES schedules are available right now.'),
        )
      else
        _dropdown(
          label: 'Select a Saturday',
          value: _scheduleDate,
          items: items,
          required: true,
          enabled: !_schedulePassed,
          onChanged: (v) => setState(() => _scheduleDate = v),
        ),
      Row(
        children: [
          const Icon(Icons.place_outlined, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text('Venue: $_venue')),
        ],
      ),
      if ((_saved?.referenceNo ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Reference: ${_saved!.referenceNo}',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    ]);
  }

  Widget _actions() {
    final saved = _saved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: (_busy || _schedulePassed || _approved) ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(
            saved == null
                ? 'Submit PMES application'
                : _rejected
                    ? 'Edit and resubmit'
                    : 'Update application',
          ),
        ),
        if (_approved)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Approved applications cannot be changed. You can still print or save the PDF.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (saved != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _print,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Save PDF'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Print or save the PDF and bring it on your PMES schedule.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PMES Application')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (_saved != null) _statusCard(),
                    _scheduleCard(),
                    _card('Personal na Impormasyon', [
                      _dropdown(
                        label: 'Uri ng Miyembro',
                        value: _category,
                        required: true,
                        items: const {
                          'ARB': 'ARB',
                          'ARB_HH': 'ARB HH',
                          'NON_ARB': 'NON-ARB',
                        },
                        onChanged: (v) => setState(() => _category = v),
                      ),
                      _tf(_lastName, 'Apelyido', required: true),
                      _tf(_firstName, 'Pangalan', required: true),
                      _tf(_middleName, 'Panggitnang Pangalan'),
                      _tf(_address, 'Tirahan', required: true, maxLines: 2),
                      _dateField(_birthDate, 'Kapanganakan', _pickBirthDate,
                          required: true),
                      _tf(_birthPlace, 'Lugar Kung Saan Ipinanganak',
                          required: true),
                      _dropdown(
                        label: 'Civil Status',
                        value: _civilStatus,
                        required: true,
                        items: const {
                          'SINGLE': 'Single',
                          'MARRIED': 'Married',
                          'WIDOW': 'Widow',
                          'SEPARATED': 'Separated',
                        },
                        onChanged: (v) => setState(() => _civilStatus = v),
                      ),
                      _dropdown(
                        label: 'Kasarian',
                        value: _sex,
                        required: true,
                        items: const {'MALE': 'Lalaki', 'FEMALE': 'Babae'},
                        onChanged: (v) => setState(() => _sex = v),
                      ),
                      _tf(_nationality, 'Nasyonalidad', required: true),
                      _tf(_phone, 'Numero ng Telepono/Cellphone',
                          required: true, keyboard: TextInputType.phone),
                      _tf(_religion, 'Relihiyon'),
                      _row([
                        _tf(_weight, 'Timbang'),
                        _tf(_height, 'Taas'),
                      ]),
                      _tf(_occupation, 'Saan Nagtatrabaho'),
                    ]),
                    _card('Pamilya', [
                      _tf(_motherName, 'Pangalan ng Ina (NUNG DALAGA)'),
                      _tf(_motherOccupation, 'Trabaho ng Ina'),
                      _tf(_fatherName, 'Pangalan ng Ama'),
                      _tf(_fatherOccupation, 'Trabaho ng Ama'),
                      _tf(_spouseName, 'Pangalan ng Asawa'),
                      _tf(_spouseOccupation, 'Trabaho ng Asawa'),
                    ]),
                    _card('Mga Benepisyaryo', [
                      for (var i = 0; i < 3; i++) _beneficiarySection(i),
                    ]),
                    _card('Pinag-aralan at Paaralan', [
                      _educationRow('Kolehiyo', _collegeSchool, _collegeYear),
                      _educationRow('Bokasyonal', _vocationalSchool, _vocationalYear),
                      _educationRow('Sekondarya', _secondarySchool, _secondaryYear),
                      _educationRow('Elementarya', _elementarySchool, _elementaryYear),
                    ]),
                    _card('Pagkakakilanlan', [
                      _tf(_tin, 'TIN'),
                      _tf(_pagibig, 'PAG-IBIG #'),
                      _tf(_sss, 'SSS #'),
                      _tf(_philhealth, 'PHILHEALTH #'),
                      _tf(_seniorId, 'SENIOR ID #'),
                      _tf(_nationalId, 'NATIONAL ID'),
                      _tf(_otherId, "IBA PA (VOTER'S/PWD /etc.)"),
                    ]),
                    _card('Pirma', [
                      _tf(_signatureName, 'Pangalan at Pirma', required: true),
                      const Text(
                        'By typing your name, you confirm that the information above is true and correct.',
                      ),
                    ]),
                    _actions(),
                  ],
                ),
              ),
            ),
    );
  }
}

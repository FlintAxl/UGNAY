import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pmes_api.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _value(String v) => v.trim().isEmpty ? '-' : v.trim();

String _fmtDate(String iso) {
  if (iso.trim().isEmpty) return '-';
  final raw = iso.length >= 10 ? iso.substring(0, 10) : iso;
  final d = DateTime.tryParse(raw);
  if (d == null) return raw;
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

pw.TextStyle get _body => const pw.TextStyle(fontSize: 9);
pw.TextStyle get _small => const pw.TextStyle(fontSize: 8);
pw.TextStyle get _labelStyle => const pw.TextStyle(fontSize: 8, color: PdfColors.grey700);
pw.TextStyle get _sectionStyle =>
    const pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold);
pw.TextStyle get _headerStyle =>
    const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);

pw.Widget _field(String label, String value, {int flex = 1}) => pw.Expanded(
      flex: flex,
      child: pw.Padding(
        padding: const pw.EdgeInsets.only(right: 10, bottom: 7),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: _labelStyle),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.only(bottom: 2),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(width: 0.6, color: PdfColors.grey600),
                ),
              ),
              child: pw.Text(_value(value), style: _body),
            ),
          ],
        ),
      ),
    );

pw.Widget _signatureField(String name, Uint8List? signatureImage, {int flex = 2}) =>
    pw.Expanded(
      flex: flex,
      child: pw.Padding(
        padding: const pw.EdgeInsets.only(right: 10, bottom: 7),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Pangalan at Pirma', style: _labelStyle),
            if (signatureImage != null)
              pw.Container(
                height: 50,
                alignment: pw.Alignment.centerLeft,
                child: pw.Image(
                  pw.MemoryImage(signatureImage),
                  fit: pw.BoxFit.contain,
                ),
              )
            else
              pw.SizedBox(height: 50),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.only(bottom: 2),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(width: 0.6, color: PdfColors.grey600),
                ),
              ),
              child: pw.Text(_value(name), style: _body),
            ),
          ],
        ),
      ),
    );

pw.Widget _check(String label, bool checked) => pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 10,
          height: 10,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.8, color: PdfColors.grey700),
          ),
          child: checked
              ? pw.Center(
                  child: pw.Text('X',
                      style: const pw.TextStyle(
                          fontSize: 7, fontWeight: pw.FontWeight.bold)))
              : null,
        ),
        pw.SizedBox(width: 4),
        pw.Text(label, style: _body),
        pw.SizedBox(width: 12),
      ],
    );

pw.Widget _section(String title, List<pw.Widget> children) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 10),
        pw.Text(title, style: _sectionStyle),
        pw.SizedBox(height: 2),
        pw.Container(height: 0.8, color: PdfColors.grey500),
        pw.SizedBox(height: 6),
        ...children,
      ],
    );

pw.Widget _cell(String text, {bool header = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        text,
        style: header
            ? const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)
            : _small,
      ),
    );

pw.Widget _header(PmesApplication a) {
  final category = a.membershipCategory;
  return pw.Column(
    children: [
      pw.Text('PRIC MPC (2000)', style: _headerStyle),
      pw.SizedBox(height: 2),
      pw.Text('Barangay Pinagdanlayan, Dolores, Quezon', style: _small),
      pw.Text('CDA Reg.: 9520-04002265  |  TIN: 005-343-410-000', style: _small),
      pw.Text('www.hillside-pricmpc.com  |  (042) 5656933 / 0919-0091240',
          style: _small),
      pw.SizedBox(height: 10),
      pw.Text('PERSONAL INFORMATION SHEET', style: _headerStyle),
      pw.SizedBox(height: 8),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          _check('ARB', category == 'ARB'),
          _check('ARB HH', category == 'ARB_HH'),
          _check('NON-ARB', category == 'NON_ARB'),
        ],
      ),
    ],
  );
}

pw.Widget _beneficiaries(PmesApplication a) {
  final rows = <pw.TableRow>[
    pw.TableRow(children: [
      _cell('Benepisyaryo', header: true),
      _cell('Kaugnayan', header: true),
      _cell('Kapanganakan', header: true),
    ]),
  ];
  for (var i = 0; i < 3; i++) {
    final b = i < a.beneficiaries.length ? a.beneficiaries[i] : null;
    rows.add(pw.TableRow(children: [
      _cell(b == null ? '' : _value(b.name)),
      _cell(b == null ? '' : _value(b.relationship)),
      _cell(b == null ? '' : _fmtDate(b.birthDate)),
    ]));
  }
  return pw.Table(
    border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey500),
    columnWidths: {
      0: const pw.FlexColumnWidth(3),
      1: const pw.FlexColumnWidth(2),
      2: const pw.FlexColumnWidth(2),
    },
    children: rows,
  );
}

pw.Widget _education(PmesApplication a) {
  final e = a.education;
  final rows = <pw.TableRow>[
    pw.TableRow(children: [
      _cell('PINAG-ARALAN at PAARALAN', header: true),
      _cell('Taon ng Pagtatapos', header: true),
    ]),
    pw.TableRow(children: [
      _cell('Kolehiyo: ${_value(e.college.school)}'),
      _cell(_value(e.college.yearGraduated)),
    ]),
    pw.TableRow(children: [
      _cell('Bokasyonal: ${_value(e.vocational.school)}'),
      _cell(_value(e.vocational.yearGraduated)),
    ]),
    pw.TableRow(children: [
      _cell('Sekondarya: ${_value(e.secondary.school)}'),
      _cell(_value(e.secondary.yearGraduated)),
    ]),
    pw.TableRow(children: [
      _cell('Elementarya: ${_value(e.elementary.school)}'),
      _cell(_value(e.elementary.yearGraduated)),
    ]),
  ];
  return pw.Table(
    border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey500),
    columnWidths: {
      0: const pw.FlexColumnWidth(5),
      1: const pw.FlexColumnWidth(2),
    },
    children: rows,
  );
}

Future<Uint8List> buildPmesPdf(PmesApplication a,
    {Uint8List? signatureImage}) async {
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'PMES Application ${_value(a.referenceNo ?? '')}  |  Page ${context.pageNumber} of ${context.pagesCount}',
          style: _small,
        ),
      ),
      build: (context) => [
        _header(a),
        _section('PERSONAL NA IMPORMASYON', [
          pw.Row(children: [
            _field('Apelyido', a.lastName),
            _field('Pangalan', a.firstName),
            _field('Panggitnang Pangalan', a.middleName),
          ]),
          pw.Row(children: [_field('Tirahan', a.address, flex: 3)]),
          pw.Row(children: [
            _field('Kapanganakan', _fmtDate(a.birthDate)),
            _field('Lugar Kung Saan Ipinanganak', a.birthPlace, flex: 2),
          ]),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 7),
            child: pw.Row(children: [
              pw.SizedBox(
                width: 90,
                child: pw.Text('Civil Status', style: _labelStyle),
              ),
              _check('Single', a.civilStatus == 'SINGLE'),
              _check('Married', a.civilStatus == 'MARRIED'),
              _check('Widow', a.civilStatus == 'WIDOW'),
              _check('Separated', a.civilStatus == 'SEPARATED'),
            ]),
          ),
          pw.Row(children: [
            _field('Relihiyon', a.religion),
            _field('Timbang', a.weight),
            _field('Taas', a.height),
          ]),
          pw.Row(children: [
            _field('Kasarian', a.sex == 'MALE' ? 'Lalaki' : (a.sex == 'FEMALE' ? 'Babae' : '')),
            _field('Nasyonalidad', a.nationality),
          ]),
          pw.Row(children: [
            _field('Numero ng Telepono/Cellphone', a.phone),
          ]),
          pw.Row(children: [
            _field('Saan Nagtatrabaho', a.occupation, flex: 3),
          ]),
        ]),
        _section('PAMILYA', [
          pw.Row(children: [
            _field('Pangalan ng Ina (NUNG DALAGA)', a.motherName, flex: 2),
            _field('Trabaho', a.motherOccupation),
          ]),
          pw.Row(children: [
            _field('Pangalan ng Ama', a.fatherName, flex: 2),
            _field('Trabaho', a.fatherOccupation),
          ]),
          pw.Row(children: [
            _field('Pangalan ng Asawa', a.spouseName, flex: 2),
            _field('Trabaho', a.spouseOccupation),
          ]),
        ]),
        _section('MGA BENEPISYARYO', [_beneficiaries(a)]),
        _section('IBA PANG IMPORMASYON', [
          pw.Text('PINAG-ARALAN at PAARALAN', style: _labelStyle),
          pw.SizedBox(height: 3),
          _education(a),
        ]),
        _section('PAGKAKAKILANLAN', [
          pw.Row(children: [
            _field('TIN', a.ids.tin),
            _field('PAG-IBIG #', a.ids.pagibig),
          ]),
          pw.Row(children: [
            _field('SSS #', a.ids.sss),
            _field('PHILHEALTH #', a.ids.philhealth),
          ]),
          pw.Row(children: [
            _field('SENIOR ID #', a.ids.seniorId),
            _field('NATIONAL ID', a.ids.nationalId),
          ]),
          pw.Row(children: [
            _field("IBA PA (VOTER'S/PWD /etc.)", a.ids.other, flex: 2),
          ]),
        ]),
        _section('PMES SCHEDULE', [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.8, color: PdfColors.green700),
              color: PdfColors.green50,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Schedule date: ${_fmtDate(a.scheduleDate)} (Saturday)',
                  style: const pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 2),
                pw.Text('Venue: ${_value(a.venue)}', style: _body),
                if ((a.referenceNo ?? '').isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text('Reference: ${a.referenceNo}', style: _small),
                ],
              ],
            ),
          ),
        ]),
        _section('PIRMA', [
          pw.SizedBox(height: 12),
          pw.Row(children: [
            _signatureField(a.signatureName, signatureImage),
            _field('Petsa', _fmtDate(a.createdAt ?? '')),
          ]),
          pw.SizedBox(height: 8),
          pw.Text(
            'This form was generated by the Ugnay portal. Please print and bring it on your PMES schedule.',
            style: _small,
          ),
        ]),
      ],
    ),
  );

  return doc.save();
}

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'logistics_api.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _value(String? v) {
  final s = (v ?? '').trim();
  return s.isEmpty ? '-' : s;
}

String _fmtDateTime(String? iso) {
  if (iso == null || iso.trim().isEmpty) return '-';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso.length >= 10 ? iso.substring(0, 10) : iso;
  final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final ap = dt.hour < 12 ? 'AM' : 'PM';
  final min = dt.minute.toString().padLeft(2, '0');
  return '${_months[dt.month - 1]} ${dt.day}, ${dt.year} $h12:$min $ap';
}

String _prefix(String status) {
  switch (status) {
    case 'DRAFT':
      return 'DOWN PAYMENT RECEIPT';
    case 'RELEASED':
      return 'RENTAL RELEASE RECEIPT';
    case 'RETURNED':
      return 'RENTAL RETURN RECEIPT';
    case 'CANCELLED':
      return 'RENTAL RECORD (CANCELLED)';
    default:
      return 'RENTAL RECEIPT';
  }
}

bool _positive(String v) => (double.tryParse(v) ?? 0) > 0;

pw.TextStyle get _body => const pw.TextStyle(fontSize: 8.5);
pw.TextStyle get _small => const pw.TextStyle(fontSize: 7.5);
pw.TextStyle get _labelStyle =>
    const pw.TextStyle(fontSize: 7, color: PdfColors.grey700);
pw.TextStyle get _sectionStyle =>
    const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
pw.TextStyle get _titleStyle =>
    const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold);
pw.TextStyle get _companyStyle =>
    const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);

pw.Widget _header(RentalDetail r) => pw.Column(
  children: [
    pw.Text('PRIC MPC (2000)', style: _companyStyle),
    pw.SizedBox(height: 2),
    pw.Text('Barangay Pinagdanlayan, Dolores, Quezon', style: _small),
    pw.Text('CDA Reg.: 9520-04002265  |  TIN: 005-343-410-000', style: _small),
    pw.Text(
      'www.hillside-pricmpc.com  |  (042) 5656933 / 0919-0091240',
      style: _small,
    ),
    pw.SizedBox(height: 10),
    pw.Text(_prefix(r.status), style: _titleStyle),
    pw.SizedBox(height: 8),
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(width: 0.6, color: PdfColors.grey500),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Receipt No: ${_value(r.rentalNo)}', style: _body),
          pw.Text('Status: ${_value(r.status)}', style: _body),
        ],
      ),
    ),
  ],
);

pw.Widget _section(String title, List<pw.Widget> children) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.SizedBox(height: 9),
    pw.Text(title, style: _sectionStyle),
    pw.SizedBox(height: 2),
    pw.Container(height: 0.7, color: PdfColors.grey500),
    pw.SizedBox(height: 5),
    ...children,
  ],
);

pw.Widget _infoRow(String label, String? value) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 2),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(width: 76, child: pw.Text(label, style: _labelStyle)),
      pw.Expanded(child: pw.Text(_value(value), style: _body)),
    ],
  ),
);

pw.Widget _moneyRow(
  String label,
  String value, {
  bool bold = false,
  bool muted = false,
}) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 2),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        label,
        style: bold
            ? const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)
            : _body,
      ),
      pw.Text(
        'PHP $value',
        style: muted
            ? _small
            : (bold
                  ? const pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    )
                  : _body),
      ),
    ],
  ),
);

pw.Widget _cell(
  String text, {
  bool header = false,
  bool right = false,
  bool bold = false,
}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 3),
  child: pw.Text(
    text,
    textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
    style: header
        ? const pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)
        : (bold
              ? const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)
              : _small),
  ),
);

pw.Widget _itemsTable(RentalDetail r) {
  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        _cell('Item', header: true),
        _cell('Qty / Unit', header: true, right: true),
        _cell('Unit Price', header: true, right: true),
        _cell('Amount', header: true, right: true),
      ],
    ),
  ];
  for (final item in r.items) {
    rows.add(
      pw.TableRow(
        children: [
          _cell(item.name),
          _cell('${item.quantity} ${item.unit}', right: true),
          _cell('PHP ${item.unitPrice}', right: true),
          _cell('PHP ${item.amount}', right: true, bold: true),
        ],
      ),
    );
  }
  final table = pw.Table(
    border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey500),
    columnWidths: {
      0: const pw.FlexColumnWidth(3.4),
      1: const pw.FlexColumnWidth(1.4),
      2: const pw.FlexColumnWidth(1.6),
      3: const pw.FlexColumnWidth(1.6),
    },
    children: rows,
  );
  if (r.status != 'RETURNED') return table;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      table,
      pw.SizedBox(height: 4),
      for (final item in r.items)
        pw.Text(
          '${item.name}: returned ${item.returned}, lost ${item.lost}, damaged ${item.damaged}'
          '${_positive(item.charge) ? ', charge PHP ${item.charge}' : ''}',
          style: _small,
        ),
    ],
  );
}

pw.Widget _payments(RentalDetail r) {
  if (r.payments.isEmpty) {
    return pw.Text(
      'No payments recorded yet.',
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
    );
  }
  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        _cell('Date', header: true),
        _cell('Description', header: true),
        _cell('Amount', header: true, right: true),
      ],
    ),
  ];
  for (final p in r.payments) {
    final desc = <String>[
      p.kind.replaceAll('_', ' '),
      if ((p.note ?? '').trim().isNotEmpty) p.note!.trim(),
      if ((p.receivedByName ?? '').trim().isNotEmpty)
        'received by ${p.receivedByName!.trim()}',
    ].join(' • ');
    rows.add(
      pw.TableRow(
        children: [
          _cell(_fmtDateTime(p.at)),
          _cell(desc),
          _cell('PHP ${p.amount}', right: true, bold: true),
        ],
      ),
    );
  }
  return pw.Table(
    border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey500),
    columnWidths: {
      0: const pw.FlexColumnWidth(2.1),
      1: const pw.FlexColumnWidth(3.6),
      2: const pw.FlexColumnWidth(1.5),
    },
    children: rows,
  );
}

pw.Widget _signatureColumn(
  String label,
  String name,
  String meta,
  Uint8List? image,
) => pw.Expanded(
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: _labelStyle),
      pw.SizedBox(height: 2),
      if (image != null)
        pw.Container(
          height: 42,
          alignment: pw.Alignment.centerLeft,
          child: pw.Image(pw.MemoryImage(image), fit: pw.BoxFit.contain),
        )
      else
        pw.SizedBox(height: 42),
      pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(width: 0.6, color: PdfColors.grey600),
          ),
        ),
        padding: const pw.EdgeInsets.only(top: 2),
        child: pw.Text(_value(name), style: _body),
      ),
      pw.Text(meta, style: _small),
    ],
  ),
);

Future<Uint8List> buildRentalReceiptPdf(
  RentalDetail r, {
  Uint8List? signatureImage,
}) async {
  final doc = pw.Document();
  final signed = r.signature;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(20),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated by Ugnay  |  ${_fmtDateTime(DateTime.now().toIso8601String())}',
            style: _small,
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: _small,
          ),
        ],
      ),
      build: (context) => [
        _header(r),
        _section('BORROWER & EVENT', [
          _infoRow('Borrower', r.borrowerName),
          if ((r.borrowerPhone ?? '').isNotEmpty)
            _infoRow('Phone', r.borrowerPhone),
          if ((r.memberName ?? '').isNotEmpty) _infoRow('Member', r.memberName),
          if ((r.referredBy ?? '').isNotEmpty)
            _infoRow('Referred By', r.referredBy),
          _infoRow('Venue', r.venue),
          _infoRow('Pickup At', _fmtDateTime(r.pickupAt)),
          _infoRow('Due At', _fmtDateTime(r.dueAt)),
          if (r.releasedAt != null)
            _infoRow('Released At', _fmtDateTime(r.releasedAt)),
          if (r.returnedAt != null)
            _infoRow('Returned At', _fmtDateTime(r.returnedAt)),
          if ((r.preparedByName ?? '').isNotEmpty)
            _infoRow('Prepared By', r.preparedByName),
        ]),
        _section('ITEMS', [_itemsTable(r)]),
        _section('FINANCIALS', [
          _moneyRow('Rental Cost', r.rentalCost),
          if (_positive(r.penalty))
            _moneyRow('Late Penalty (${r.daysLate} day/s)', r.penalty),
          if (_positive(r.otherCharges))
            _moneyRow('Damage / Lost Charges', r.otherCharges),
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 3),
            height: 0.6,
            color: PdfColors.grey500,
          ),
          _moneyRow('Total Due', r.totalDue, bold: true),
          _moneyRow('Total Paid', r.totalPaid),
          _moneyRow('Balance Remaining', r.balance, bold: true),
          if (r.status == 'DRAFT') ...[
            pw.SizedBox(height: 3),
            pw.Text(
              'Minimum 50% down payment required: PHP ${r.minDownPayment}',
              style: _small,
            ),
          ],
        ]),
        _section('PAYMENTS', [_payments(r)]),
        _section('SIGNATURES', [
          pw.SizedBox(height: 6),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _signatureColumn(
                "Borrower's Signature",
                r.borrowerName,
                signed == null
                    ? 'Not signed'
                    : 'Signed ${_fmtDateTime(signed.signedAt)} (Terms v${signed.termsVersion})',
                signatureImage,
              ),
              pw.SizedBox(width: 16),
              _signatureColumn(
                'Received / Released by',
                r.preparedByName ?? '',
                signed == null
                    ? 'Cooperative representative'
                    : 'Cooperative representative',
                null,
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'This receipt is a copy for the borrower. Please keep it for your records.',
            style: _small,
          ),
        ]),
      ],
    ),
  );

  return doc.save();
}

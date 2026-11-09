import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';

// ============================================================ Logistics Models

class LogisticsSummary {
  final int out;
  final int overdue;
  final int unpaidReturned;
  final int drafts;
  final int activeItems;

  const LogisticsSummary({
    required this.out,
    required this.overdue,
    required this.unpaidReturned,
    required this.drafts,
    required this.activeItems,
  });

  factory LogisticsSummary.fromJson(Map<String, dynamic> j) => LogisticsSummary(
        out: (j['out'] as num?)?.toInt() ?? 0,
        overdue: (j['overdue'] as num?)?.toInt() ?? 0,
        unpaidReturned: (j['unpaid_returned'] as num?)?.toInt() ?? 0,
        drafts: (j['drafts'] as num?)?.toInt() ?? 0,
        activeItems: (j['active_items'] as num?)?.toInt() ?? 0,
      );
}

class InventoryItem {
  final String id;
  final String name;
  final String category; // EQUIPMENT | COVER_AND_TELA
  final String unit; // pc | yard
  final String price;
  final String totalQuantity;
  final String availableQuantity;
  final String outQuantity;
  final bool isActive;

  const InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.price,
    required this.totalQuantity,
    required this.availableQuantity,
    required this.outQuantity,
    required this.isActive,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
        id: j['id'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        unit: j['unit'] as String,
        price: (j['price'] ?? '0.00').toString(),
        totalQuantity: (j['total_quantity'] ?? '0').toString(),
        availableQuantity: (j['available_quantity'] ?? '0').toString(),
        outQuantity: (j['out_quantity'] ?? '0').toString(),
        isActive: j['is_active'] as bool? ?? true,
      );
}

class RentalSummary {
  final String id;
  final String rentalNo;
  final String status;
  final String borrowerName;
  final String? memberName;
  final String pickupAt;
  final String? dueAt;
  final bool isOverdue;
  final int daysLate;
  final int itemCount;
  final String totalDue;
  final String totalPaid;
  final String balance;

  const RentalSummary({
    required this.id,
    required this.rentalNo,
    required this.status,
    required this.borrowerName,
    this.memberName,
    required this.pickupAt,
    this.dueAt,
    required this.isOverdue,
    required this.daysLate,
    required this.itemCount,
    required this.totalDue,
    required this.totalPaid,
    required this.balance,
  });

  factory RentalSummary.fromJson(Map<String, dynamic> j) => RentalSummary(
        id: j['id'] as String,
        rentalNo: j['rental_no'] as String,
        status: j['status'] as String,
        borrowerName: j['borrower_name'] as String,
        memberName: j['member_name'] as String?,
        pickupAt: (j['pickup_at'] ?? '').toString(),
        dueAt: j['due_at']?.toString(),
        isOverdue: j['is_overdue'] as bool? ?? false,
        daysLate: (j['days_late'] as num?)?.toInt() ?? 0,
        itemCount: (j['item_count'] as num?)?.toInt() ?? 0,
        totalDue: (j['total_due'] ?? '0.00').toString(),
        totalPaid: (j['total_paid'] ?? '0.00').toString(),
        balance: (j['balance'] ?? '0.00').toString(),
      );
}

class RentalDetailItem {
  final String itemId;
  final String name;
  final String unit;
  final String quantity;
  final String unitPrice;
  final String amount;
  final String returned;
  final String lost;
  final String damaged;
  final String charge;

  const RentalDetailItem({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
    required this.returned,
    required this.lost,
    required this.damaged,
    required this.charge,
  });

  factory RentalDetailItem.fromJson(Map<String, dynamic> j) => RentalDetailItem(
        itemId: j['item_id'] as String,
        name: j['name'] as String,
        unit: j['unit'] as String,
        quantity: (j['quantity'] ?? '0').toString(),
        unitPrice: (j['unit_price'] ?? '0.00').toString(),
        amount: (j['amount'] ?? '0.00').toString(),
        returned: (j['returned'] ?? '0').toString(),
        lost: (j['lost'] ?? '0').toString(),
        damaged: (j['damaged'] ?? '0').toString(),
        charge: (j['charge'] ?? '0.00').toString(),
      );
}

class PaymentRecord {
  final String amount;
  final String kind;
  final String? note;
  final String? receivedByName;
  final String at;

  const PaymentRecord({
    required this.amount,
    required this.kind,
    this.note,
    this.receivedByName,
    required this.at,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> j) => PaymentRecord(
        amount: (j['amount'] ?? '0.00').toString(),
        kind: j['kind'] as String,
        note: j['note'] as String?,
        receivedByName: j['received_by_name'] as String?,
        at: (j['at'] ?? '').toString(),
      );
}

class SignatureInfo {
  final String signedAt;
  final String termsVersion;
  final String signedByName;
  final String url;

  const SignatureInfo({
    required this.signedAt,
    required this.termsVersion,
    required this.signedByName,
    required this.url,
  });

  factory SignatureInfo.fromJson(Map<String, dynamic> j) => SignatureInfo(
        signedAt: (j['signed_at'] ?? '').toString(),
        termsVersion: j['terms_version'] as String,
        signedByName: j['signed_by_name'] as String,
        url: j['url'] as String,
      );
}

class RentalDetail extends RentalSummary {
  final String? borrowerPhone;
  final String? referredBy;
  final String venue;
  final String? releasedAt;
  final String? returnedAt;
  final String? preparedByName;
  final String rentalCost;
  final String penalty;
  final String otherCharges;
  final String minDownPayment;
  final List<RentalDetailItem> items;
  final List<PaymentRecord> payments;
  final SignatureInfo? signature;

  const RentalDetail({
    required super.id,
    required super.rentalNo,
    required super.status,
    required super.borrowerName,
    super.memberName,
    required super.pickupAt,
    super.dueAt,
    required super.isOverdue,
    required super.daysLate,
    required super.itemCount,
    required super.totalDue,
    required super.totalPaid,
    required super.balance,
    this.borrowerPhone,
    this.referredBy,
    required this.venue,
    this.releasedAt,
    this.returnedAt,
    this.preparedByName,
    required this.rentalCost,
    required this.penalty,
    required this.otherCharges,
    required this.minDownPayment,
    required this.items,
    required this.payments,
    this.signature,
  });

  factory RentalDetail.fromJson(Map<String, dynamic> j) => RentalDetail(
        id: j['id'] as String,
        rentalNo: j['rental_no'] as String,
        status: j['status'] as String,
        borrowerName: j['borrower_name'] as String,
        memberName: j['member_name'] as String?,
        pickupAt: (j['pickup_at'] ?? '').toString(),
        dueAt: j['due_at']?.toString(),
        isOverdue: j['is_overdue'] as bool? ?? false,
        daysLate: (j['days_late'] as num?)?.toInt() ?? 0,
        itemCount: (j['item_count'] as num?)?.toInt() ?? 0,
        totalDue: (j['total_due'] ?? '0.00').toString(),
        totalPaid: (j['total_paid'] ?? '0.00').toString(),
        balance: (j['balance'] ?? '0.00').toString(),
        borrowerPhone: j['borrower_phone'] as String?,
        referredBy: j['referred_by'] as String?,
        venue: (j['venue'] ?? '').toString(),
        releasedAt: j['released_at']?.toString(),
        returnedAt: j['returned_at']?.toString(),
        preparedByName: j['prepared_by_name'] as String?,
        rentalCost: (j['rental_cost'] ?? '0.00').toString(),
        penalty: (j['penalty'] ?? '0.00').toString(),
        otherCharges: (j['other_charges'] ?? '0.00').toString(),
        minDownPayment: (j['min_down_payment'] ?? '0.00').toString(),
        items: ((j['items'] as List?) ?? [])
            .map((e) => RentalDetailItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        payments: ((j['payments'] as List?) ?? [])
            .map((e) => PaymentRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        signature: j['signature'] != null
            ? SignatureInfo.fromJson(Map<String, dynamic>.from(j['signature'] as Map))
            : null,
      );
}

class TermsData {
  final String version;
  final List<String> terms;

  const TermsData({required this.version, required this.terms});

  factory TermsData.fromJson(Map<String, dynamic> j) => TermsData(
        version: j['version'] as String,
        terms: ((j['terms'] as List?) ?? []).map((e) => e.toString()).toList(),
      );
}

// ============================================================ Logistics API

Future<LogisticsSummary> getLogisticsSummary() async {
  try {
    final res = await dio.get('/logistics/summary');
    return LogisticsSummary.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<List<InventoryItem>> listInventoryItems({
  bool activeOnly = false,
  String? category,
  String? q,
}) async {
  try {
    final params = <String, dynamic>{'active_only': activeOnly};
    if (category != null && category.isNotEmpty) params['category'] = category;
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    final res = await dio.get('/logistics/items', queryParameters: params);
    return (res.data as List)
        .map((e) => InventoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (e) {
    throw parseError(e);
  }
}

Future<InventoryItem> createInventoryItem({
  required String name,
  required String category,
  required String unit,
  required double price,
  required double totalQuantity,
}) async {
  try {
    final res = await dio.post('/logistics/items', data: {
      'name': name,
      'category': category,
      'unit': unit,
      'price': price,
      'total_quantity': totalQuantity,
    });
    return InventoryItem.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<InventoryItem> updateInventoryItem(
  String itemId, {
  String? name,
  double? price,
  bool? isActive,
}) async {
  try {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (price != null) data['price'] = price;
    if (isActive != null) data['is_active'] = isActive;
    final res = await dio.patch('/logistics/items/$itemId', data: data);
    return InventoryItem.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<InventoryItem> setInventoryStock(String itemId, double totalQuantity) async {
  try {
    final res = await dio.patch('/logistics/items/$itemId/stock', data: {
      'total_quantity': totalQuantity,
    });
    return InventoryItem.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<TermsData> getLogisticsTerms() async {
  try {
    final res = await dio.get('/logistics/terms');
    return TermsData.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<List<RentalSummary>> listRentals({
  String status = 'OUT',
  String? q,
}) async {
  try {
    final params = <String, dynamic>{'status': status};
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    final res = await dio.get('/logistics/rentals', queryParameters: params);
    return (res.data as List)
        .map((e) => RentalSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (e) {
    throw parseError(e);
  }
}

Future<RentalDetail> getRentalDetail(String id) async {
  try {
    final res = await dio.get('/logistics/rentals/$id');
    return RentalDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<RentalDetail> createRental({
  required String borrowerName,
  String? borrowerPhone,
  String? memberName,
  String? referredBy,
  required String venue,
  required DateTime pickupAt,
  required List<Map<String, dynamic>> items,
}) async {
  try {
    final res = await dio.post('/logistics/rentals', data: {
      'borrower_name': borrowerName,
      'borrower_phone': borrowerPhone,
      'member_name': memberName,
      'referred_by': referredBy,
      'venue': venue,
      'pickup_at': pickupAt.toUtc().toIso8601String(),
      'items': items,
    });
    return RentalDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<RentalDetail> signRental(
  String rentalId, {
  required bool agreed,
  required Uint8List imageBytes,
  String filename = 'signature.png',
}) async {
  try {
    final formData = FormData.fromMap({
      'agreed': agreed.toString(),
      'image': MultipartFile.fromBytes(imageBytes, filename: filename),
    });
    final res = await dio.post('/logistics/rentals/$rentalId/signature', data: formData);
    return RentalDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<RentalDetail> addRentalPayment(
  String rentalId, {
  required double amount,
  String? note,
}) async {
  try {
    final res = await dio.post('/logistics/rentals/$rentalId/payments', data: {
      'amount': amount,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return RentalDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<RentalDetail> releaseRental(
  String rentalId, {
  bool overrideWeekend = false,
}) async {
  try {
    final res = await dio.post('/logistics/rentals/$rentalId/release', data: {
      'override_weekend': overrideWeekend,
    });
    return RentalDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<RentalDetail> returnRental(
  String rentalId, {
  required List<Map<String, dynamic>> lines,
  bool overrideWeekend = false,
}) async {
  try {
    final res = await dio.post('/logistics/rentals/$rentalId/return', data: {
      'lines': lines,
      'override_weekend': overrideWeekend,
    });
    return RentalDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<void> cancelRental(String rentalId) async {
  try {
    await dio.post('/logistics/rentals/$rentalId/cancel');
  } catch (e) {
    throw parseError(e);
  }
}

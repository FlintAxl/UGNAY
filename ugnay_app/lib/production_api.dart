import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';

double _num(Object? v) => double.tryParse((v ?? '').toString()) ?? 0.0;

// ============================================================ Models

class Supplier {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? notes;
  final bool isActive;

  const Supplier({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.notes,
    required this.isActive,
  });

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String?,
        address: j['address'] as String?,
        notes: j['notes'] as String?,
        isActive: j['is_active'] as bool? ?? true,
      );
}

class ProductionSummary {
  final int openRounds;
  final int awardedRounds;
  final int activeSuppliers;

  const ProductionSummary({
    required this.openRounds,
    required this.awardedRounds,
    required this.activeSuppliers,
  });

  factory ProductionSummary.fromJson(Map<String, dynamic> j) => ProductionSummary(
        openRounds: (j['open_rounds'] as num?)?.toInt() ?? 0,
        awardedRounds: (j['awarded_rounds'] as num?)?.toInt() ?? 0,
        activeSuppliers: (j['active_suppliers'] as num?)?.toInt() ?? 0,
      );
}

class EntryPhoto {
  final String photoId;
  final String url;

  const EntryPhoto({required this.photoId, required this.url});

  factory EntryPhoto.fromJson(Map<String, dynamic> j) =>
      EntryPhoto(photoId: j['photo_id'] as String, url: j['url'] as String);
}

class BidEntry {
  final String bidId;
  final String supplierId;
  final String supplierName;
  final String gingerKind; // NATIVE | HALF_NATIVE
  final String weighInKg;
  final String goodKg;
  final String badKg;
  final String pricePerKgGood;
  final String totalPrice; // good kilos x good price
  final String status; // SUBMITTED | ACCEPTED | REJECTED | WITHDRAWN
  final String? remarks;
  final String? recordedByName;
  final List<EntryPhoto> photos;

  const BidEntry({
    required this.bidId,
    required this.supplierId,
    required this.supplierName,
    required this.gingerKind,
    required this.weighInKg,
    required this.goodKg,
    required this.badKg,
    required this.pricePerKgGood,
    required this.totalPrice,
    required this.status,
    this.remarks,
    this.recordedByName,
    required this.photos,
  });

  double get goodKgNum => _num(goodKg);
  double get priceNum => _num(pricePerKgGood);
  double get totalPriceNum => _num(totalPrice);

  factory BidEntry.fromJson(Map<String, dynamic> j) => BidEntry(
        bidId: j['bid_id'] as String,
        supplierId: j['supplier_id'] as String,
        supplierName: j['supplier_name'] as String,
        gingerKind: j['ginger_kind'] as String,
        weighInKg: (j['weigh_in_kg'] ?? '0').toString(),
        goodKg: (j['good_kg'] ?? '0').toString(),
        badKg: (j['bad_kg'] ?? '0').toString(),
        pricePerKgGood: (j['price_per_kg_good'] ?? '0.00').toString(),
        totalPrice: (j['total_price'] ?? '0.00').toString(),
        status: j['status'] as String,
        remarks: j['remarks'] as String?,
        recordedByName: j['recorded_by_name'] as String?,
        photos: ((j['photos'] as List?) ?? [])
            .map((e) => EntryPhoto.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// Used for both the list (bids empty) and the detail (bids filled).
class BiddingRound {
  final String id;
  final String roundNo;
  final String? title;
  final String status; // OPEN | AWARDED | CANCELLED
  final String biddingDate;
  final int entryCount;
  final int acceptedCount;
  final String acceptedTotalPrice;
  final String createdAt;
  final String? awardedAt;
  final String? notes;
  final String? awardRemarks;
  final String? awardedByName;
  final String? createdByName;
  final String acceptedWeighInKg;
  final String acceptedGoodKg;
  final String acceptedBadKg;
  final List<BidEntry> bids;

  const BiddingRound({
    required this.id,
    required this.roundNo,
    this.title,
    required this.status,
    required this.biddingDate,
    required this.entryCount,
    required this.acceptedCount,
    required this.acceptedTotalPrice,
    required this.createdAt,
    this.awardedAt,
    this.notes,
    this.awardRemarks,
    this.awardedByName,
    this.createdByName,
    required this.acceptedWeighInKg,
    required this.acceptedGoodKg,
    required this.acceptedBadKg,
    required this.bids,
  });

  factory BiddingRound.fromJson(Map<String, dynamic> j) => BiddingRound(
        id: j['id'] as String,
        roundNo: j['round_no'] as String,
        title: j['title'] as String?,
        status: j['status'] as String,
        biddingDate: (j['bidding_date'] ?? '').toString(),
        entryCount: (j['entry_count'] as num?)?.toInt() ?? 0,
        acceptedCount: (j['accepted_count'] as num?)?.toInt() ?? 0,
        acceptedTotalPrice: (j['accepted_total_price'] ?? '0.00').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        awardedAt: j['awarded_at']?.toString(),
        notes: j['notes'] as String?,
        awardRemarks: j['award_remarks'] as String?,
        awardedByName: j['awarded_by_name'] as String?,
        createdByName: j['created_by_name'] as String?,
        acceptedWeighInKg: (j['accepted_weigh_in_kg'] ?? '0.00').toString(),
        acceptedGoodKg: (j['accepted_good_kg'] ?? '0.00').toString(),
        acceptedBadKg: (j['accepted_bad_kg'] ?? '0.00').toString(),
        bids: ((j['bids'] as List?) ?? [])
            .map((e) => BidEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

// ============================================================ API

BiddingRound _round(Response res) =>
    BiddingRound.fromJson(Map<String, dynamic>.from(res.data as Map));

Future<ProductionSummary> getProductionSummary() async {
  try {
    final res = await dio.get('/production/summary');
    return ProductionSummary.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

// ---- Suppliers

Future<List<Supplier>> listSuppliers({bool activeOnly = true, String? q}) async {
  try {
    final params = <String, dynamic>{'active_only': activeOnly};
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    final res = await dio.get('/production/suppliers', queryParameters: params);
    return (res.data as List)
        .map((e) => Supplier.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (e) {
    throw parseError(e);
  }
}

Future<Supplier> createSupplier({
  required String name,
  String? phone,
  String? address,
  String? notes,
}) async {
  try {
    final res = await dio.post('/production/suppliers', data: {
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
    });
    return Supplier.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

/// Sends every field so an emptied field is cleared on the server.
Future<Supplier> updateSupplier(
  String id, {
  required String name,
  required String phone,
  required String address,
  required String notes,
  required bool isActive,
}) async {
  try {
    final res = await dio.patch('/production/suppliers/$id', data: {
      'name': name,
      'phone': phone,
      'address': address,
      'notes': notes,
      'is_active': isActive,
    });
    return Supplier.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

// ---- Rounds

Future<List<BiddingRound>> listRounds({String status = 'OPEN', String? q}) async {
  try {
    final params = <String, dynamic>{'status': status};
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    final res = await dio.get('/production/rounds', queryParameters: params);
    return (res.data as List)
        .map((e) => BiddingRound.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (e) {
    throw parseError(e);
  }
}

Future<BiddingRound> getRound(String id) async {
  try {
    return _round(await dio.get('/production/rounds/$id'));
  } catch (e) {
    throw parseError(e);
  }
}

Future<BiddingRound> createRound({String? title, String? notes}) async {
  try {
    return _round(await dio.post('/production/rounds', data: {'title': title, 'notes': notes}));
  } catch (e) {
    throw parseError(e);
  }
}

Future<void> cancelRound(String id) async {
  try {
    await dio.post('/production/rounds/$id/cancel');
  } catch (e) {
    throw parseError(e);
  }
}

Future<BiddingRound> awardRound(
  String id, {
  required List<String> acceptedBidIds,
  String? remarks,
}) async {
  try {
    return _round(await dio.post('/production/rounds/$id/award', data: {
      'accepted_bid_ids': acceptedBidIds,
      'remarks': (remarks == null || remarks.trim().isEmpty) ? null : remarks.trim(),
    }));
  } catch (e) {
    throw parseError(e);
  }
}

// ---- Entries (one per bidder)

double _two(double v) => double.parse(v.toStringAsFixed(2));

Future<BiddingRound> addBid(
  String roundId, {
  required String supplierId,
  required String gingerKind,
  required double weighInKg,
  required double goodKg,
  required double badKg,
  required double pricePerKgGood,
  String? remarks,
}) async {
  try {
    return _round(await dio.post('/production/rounds/$roundId/bids', data: {
      'supplier_id': supplierId,
      'ginger_kind': gingerKind,
      'weigh_in_kg': _two(weighInKg),
      'good_kg': _two(goodKg),
      'bad_kg': _two(badKg),
      'price_per_kg_good': _two(pricePerKgGood),
      'remarks': (remarks == null || remarks.trim().isEmpty) ? null : remarks.trim(),
    }));
  } catch (e) {
    throw parseError(e);
  }
}

Future<BiddingRound> updateBid(
  String roundId,
  String bidId, {
  double? pricePerKgGood,
  String? remarks,
}) async {
  try {
    final data = <String, dynamic>{};
    if (pricePerKgGood != null) data['price_per_kg_good'] = _two(pricePerKgGood);
    if (remarks != null) data['remarks'] = remarks;
    return _round(await dio.patch('/production/rounds/$roundId/bids/$bidId', data: data));
  } catch (e) {
    throw parseError(e);
  }
}

Future<BiddingRound> withdrawBid(String roundId, String bidId) async {
  try {
    return _round(await dio.post('/production/rounds/$roundId/bids/$bidId/withdraw'));
  } catch (e) {
    throw parseError(e);
  }
}

Future<BiddingRound> uploadBidPhotos(
  String roundId,
  String bidId,
  List<Uint8List> photos,
) async {
  try {
    // One "files" part per photo, built explicitly so it works on every Dio version.
    final form = FormData();
    for (int i = 0; i < photos.length; i++) {
      form.files.add(MapEntry(
        'files',
        MultipartFile.fromBytes(photos[i], filename: 'ginger_${i + 1}.jpg'),
      ));
    }
    return _round(await dio.post('/production/rounds/$roundId/bids/$bidId/photos', data: form));
  } catch (e) {
    throw parseError(e);
  }
}

Future<BiddingRound> deleteBidPhoto(String roundId, String bidId, String photoId) async {
  try {
    return _round(await dio.delete('/production/rounds/$roundId/bids/$bidId/photos/$photoId'));
  } catch (e) {
    throw parseError(e);
  }
}
import 'api_client.dart';
import 'pmes_api.dart';

String _s(Object? v) => (v ?? '').toString();
String? _o(Object? v) => v?.toString();

class AdminPmesSummary {
  final String id;
  final String? referenceNo;
  final String email;
  final String? fullName;
  final String scheduleDate;
  final String status;
  final String createdAt;
  final String updatedAt;

  const AdminPmesSummary({
    required this.id,
    required this.email,
    required this.scheduleDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.referenceNo,
    this.fullName,
  });

  factory AdminPmesSummary.fromJson(Map<String, dynamic> j) => AdminPmesSummary(
        id: _s(j['id']),
        referenceNo: _o(j['reference_no']),
        email: _s(j['email']),
        fullName: _o(j['full_name']),
        scheduleDate: _s(j['schedule_date']),
        status: _s(j['status']),
        createdAt: _s(j['created_at']),
        updatedAt: _s(j['updated_at']),
      );
}

class AdminPmesApplicant {
  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String status;
  final String role;
  final String? membershipType;
  final String? idPhotoUrl;
  final String? facePhotoUrl;

  const AdminPmesApplicant({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.status,
    required this.role,
    this.membershipType,
    this.idPhotoUrl,
    this.facePhotoUrl,
  });

  factory AdminPmesApplicant.fromJson(Map<String, dynamic> j) => AdminPmesApplicant(
        id: _s(j['id']),
        fullName: _s(j['full_name']),
        email: _s(j['email']),
        phone: _s(j['phone']),
        status: _s(j['status']),
        role: _s(j['role']),
        membershipType: _o(j['membership_type']),
        idPhotoUrl: _o(j['id_photo_url']),
        facePhotoUrl: _o(j['face_photo_url']),
      );
}

class AdminPmesDetail {
  final PmesApplication application;
  final AdminPmesApplicant? applicant;

  const AdminPmesDetail({required this.application, this.applicant});

  factory AdminPmesDetail.fromJson(Map<String, dynamic> j) {
    final raw = j['applicant'];
    return AdminPmesDetail(
      application: PmesApplication.fromJson(j),
      applicant: raw == null
          ? null
          : AdminPmesApplicant.fromJson(Map<String, dynamic>.from(raw as Map)),
    );
  }
}

Future<List<AdminPmesSummary>> listAdminPmes(String status) async {
  try {
    final res = await dio.get('/admin/pmes', queryParameters: {'status': status});
    return (res.data as List)
        .map((e) => AdminPmesSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (e) {
    throw parseError(e);
  }
}

Future<AdminPmesDetail> getAdminPmes(String id) async {
  try {
    final res = await dio.get('/admin/pmes/$id');
    return AdminPmesDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<void> approveAdminPmes(String id) async {
  try {
    await dio.post('/admin/pmes/$id/approve');
  } catch (e) {
    throw parseError(e);
  }
}

Future<void> rejectAdminPmes(String id, String reason) async {
  try {
    await dio.post('/admin/pmes/$id/reject', data: {'reason': reason});
  } catch (e) {
    throw parseError(e);
  }
}

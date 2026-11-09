import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'config.dart';

String _str(Object? v) => (v ?? '').toString();
String? _opt(Object? v) => v?.toString();

// PMES uses its own plain Dio: the staff access-token interceptor must not
// overwrite the limited PMES token.
final Dio _pmesDio = Dio(BaseOptions(
  baseUrl: AppConfig.baseUrl,
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 30),
));

Options _auth(String token) => Options(headers: {'Authorization': 'Bearer $token'});

// ============================================================ Models

class PmesBeneficiary {
  final String name;
  final String relationship;
  final String birthDate;

  const PmesBeneficiary({
    this.name = '',
    this.relationship = '',
    this.birthDate = '',
  });

  factory PmesBeneficiary.fromJson(Map<String, dynamic> j) => PmesBeneficiary(
        name: _str(j['name']),
        relationship: _str(j['relationship']),
        birthDate: _str(j['birth_date']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'relationship': relationship,
        'birth_date': birthDate.isEmpty ? null : birthDate,
      };
}

class PmesEducationEntry {
  final String school;
  final String yearGraduated;

  const PmesEducationEntry({this.school = '', this.yearGraduated = ''});

  factory PmesEducationEntry.fromJson(Map<String, dynamic>? j) =>
      PmesEducationEntry(
        school: _str(j?['school']),
        yearGraduated: _str(j?['year_graduated']),
      );

  Map<String, dynamic> toJson() => {
        'school': school,
        'year_graduated': yearGraduated,
      };
}

class PmesEducation {
  final PmesEducationEntry college;
  final PmesEducationEntry vocational;
  final PmesEducationEntry secondary;
  final PmesEducationEntry elementary;

  const PmesEducation({
    this.college = const PmesEducationEntry(),
    this.vocational = const PmesEducationEntry(),
    this.secondary = const PmesEducationEntry(),
    this.elementary = const PmesEducationEntry(),
  });

  factory PmesEducation.fromJson(Map<String, dynamic> j) => PmesEducation(
        college: PmesEducationEntry.fromJson(j['college'] as Map<String, dynamic>?),
        vocational: PmesEducationEntry.fromJson(j['vocational'] as Map<String, dynamic>?),
        secondary: PmesEducationEntry.fromJson(j['secondary'] as Map<String, dynamic>?),
        elementary: PmesEducationEntry.fromJson(j['elementary'] as Map<String, dynamic>?),
      );

  Map<String, dynamic> toJson() => {
        'college': college.toJson(),
        'vocational': vocational.toJson(),
        'secondary': secondary.toJson(),
        'elementary': elementary.toJson(),
      };
}

class PmesIds {
  final String tin;
  final String pagibig;
  final String sss;
  final String philhealth;
  final String seniorId;
  final String nationalId;
  final String other;

  const PmesIds({
    this.tin = '',
    this.pagibig = '',
    this.sss = '',
    this.philhealth = '',
    this.seniorId = '',
    this.nationalId = '',
    this.other = '',
  });

  factory PmesIds.fromJson(Map<String, dynamic> j) => PmesIds(
        tin: _str(j['tin']),
        pagibig: _str(j['pagibig']),
        sss: _str(j['sss']),
        philhealth: _str(j['philhealth']),
        seniorId: _str(j['senior_id']),
        nationalId: _str(j['national_id']),
        other: _str(j['other']),
      );

  Map<String, dynamic> toJson() => {
        'tin': tin,
        'pagibig': pagibig,
        'sss': sss,
        'philhealth': philhealth,
        'senior_id': seniorId,
        'national_id': nationalId,
        'other': other,
      };
}

class PmesApplication {
  final String? id;
  final String? referenceNo;
  final String? status;
  final String? email;
  final String? createdAt;
  final String? reviewedAt;
  final String? rejectionReason;

  final String membershipCategory;

  final String lastName;
  final String firstName;
  final String middleName;
  final String address;
  final String birthDate;
  final String birthPlace;
  final String civilStatus;
  final String sex;
  final String nationality;
  final String phone;
  final String religion;
  final String weight;
  final String height;
  final String occupation;

  final String motherName;
  final String motherOccupation;
  final String fatherName;
  final String fatherOccupation;
  final String spouseName;
  final String spouseOccupation;

  final List<PmesBeneficiary> beneficiaries;
  final PmesEducation education;
  final PmesIds ids;

  final String scheduleDate;
  final String venue;
  final String signatureName;
  final String signatureUrl;

  const PmesApplication({
    this.id,
    this.referenceNo,
    this.status,
    this.email,
    this.createdAt,
    this.reviewedAt,
    this.rejectionReason,
    this.membershipCategory = '',
    this.lastName = '',
    this.firstName = '',
    this.middleName = '',
    this.address = '',
    this.birthDate = '',
    this.birthPlace = '',
    this.civilStatus = '',
    this.sex = '',
    this.nationality = 'Filipino',
    this.phone = '',
    this.religion = '',
    this.weight = '',
    this.height = '',
    this.occupation = '',
    this.motherName = '',
    this.motherOccupation = '',
    this.fatherName = '',
    this.fatherOccupation = '',
    this.spouseName = '',
    this.spouseOccupation = '',
    this.beneficiaries = const [],
    this.education = const PmesEducation(),
    this.ids = const PmesIds(),
    this.scheduleDate = '',
    this.venue = '',
    this.signatureName = '',
    this.signatureUrl = '',
  });

  factory PmesApplication.fromJson(Map<String, dynamic> j) => PmesApplication(
        id: _opt(j['id']),
        referenceNo: _opt(j['reference_no']),
        status: _opt(j['status']),
        email: _opt(j['email']),
        createdAt: _opt(j['created_at']),
        reviewedAt: _opt(j['reviewed_at']),
        rejectionReason: _opt(j['rejection_reason']),
        membershipCategory: _str(j['membership_category']),
        lastName: _str(j['last_name']),
        firstName: _str(j['first_name']),
        middleName: _str(j['middle_name']),
        address: _str(j['address']),
        birthDate: _str(j['birth_date']),
        birthPlace: _str(j['birth_place']),
        civilStatus: _str(j['civil_status']),
        sex: _str(j['sex']),
        nationality: _str(j['nationality']),
        phone: _str(j['phone']),
        religion: _str(j['religion']),
        weight: _str(j['weight']),
        height: _str(j['height']),
        occupation: _str(j['occupation']),
        motherName: _str(j['mother_name']),
        motherOccupation: _str(j['mother_occupation']),
        fatherName: _str(j['father_name']),
        fatherOccupation: _str(j['father_occupation']),
        spouseName: _str(j['spouse_name']),
        spouseOccupation: _str(j['spouse_occupation']),
        beneficiaries: ((j['beneficiaries'] as List?) ?? [])
            .map((e) => PmesBeneficiary.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        education: PmesEducation.fromJson(
            Map<String, dynamic>.from((j['education'] as Map?) ?? {})),
        ids: PmesIds.fromJson(Map<String, dynamic>.from((j['ids'] as Map?) ?? {})),
        scheduleDate: _str(j['schedule_date']),
        venue: _str(j['venue']),
        signatureName: _str(j['signature_name']),
        signatureUrl: _str(j['signature_url']),
      );

  Map<String, dynamic> toJson() => {
        'membership_category': membershipCategory,
        'last_name': lastName,
        'first_name': firstName,
        'middle_name': middleName,
        'address': address,
        'birth_date': birthDate,
        'birth_place': birthPlace,
        'civil_status': civilStatus,
        'sex': sex,
        'nationality': nationality,
        'phone': phone,
        'religion': religion,
        'weight': weight,
        'height': height,
        'occupation': occupation,
        'mother_name': motherName,
        'mother_occupation': motherOccupation,
        'father_name': fatherName,
        'father_occupation': fatherOccupation,
        'spouse_name': spouseName,
        'spouse_occupation': spouseOccupation,
        'beneficiaries': beneficiaries.map((b) => b.toJson()).toList(),
        'education': education.toJson(),
        'ids': ids.toJson(),
        'schedule_date': scheduleDate,
        'signature_name': signatureName,
      };
}

class PmesScheduleOption {
  final String date;
  final String label;
  final String venue;

  const PmesScheduleOption({
    required this.date,
    required this.label,
    required this.venue,
  });

  factory PmesScheduleOption.fromJson(Map<String, dynamic> j) => PmesScheduleOption(
        date: _str(j['date']),
        label: _str(j['label']),
        venue: _str(j['venue']),
      );
}

class PmesLoginResult {
  final String token;
  final String email;
  final String fullName;
  final String status;

  const PmesLoginResult({
    required this.token,
    required this.email,
    required this.fullName,
    required this.status,
  });
}

// ============================================================ API

Future<PmesLoginResult> pmesLogin(String email, String password) async {
  try {
    final res = await _pmesDio.post('/auth/pmes-login',
        data: {'email': email, 'password': password});
    final d = Map<String, dynamic>.from(res.data as Map);
    return PmesLoginResult(
      token: _str(d['pmes_token']),
      email: _str(d['email']),
      fullName: _str(d['full_name']),
      status: _str(d['status']),
    );
  } catch (e) {
    throw parseError(e);
  }
}

Future<List<PmesScheduleOption>> getPmesScheduleOptions(
  String token, {
  int count = 12,
}) async {
  try {
    final res = await _pmesDio.get('/pmes/schedule-options',
        queryParameters: {'count': count}, options: _auth(token));
    return (res.data as List)
        .map((e) => PmesScheduleOption.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (e) {
    throw parseError(e);
  }
}

Future<PmesApplication?> getPmesApplication(String token) async {
  try {
    final res = await _pmesDio.get('/pmes/application', options: _auth(token));
    final d = Map<String, dynamic>.from(res.data as Map);
    final app = d['application'];
    return app == null
        ? null
        : PmesApplication.fromJson(Map<String, dynamic>.from(app as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<PmesApplication> savePmesApplication(
    String token, PmesApplication application,
    {Uint8List? signaturePng}) async {
  try {
    final data = application.toJson();
    if (signaturePng != null) {
      data['signature_image'] = base64Encode(signaturePng);
    }
    final res = await _pmesDio.put('/pmes/application',
        data: data, options: _auth(token));
    final d = Map<String, dynamic>.from(res.data as Map);
    return PmesApplication.fromJson(
        Map<String, dynamic>.from(d['application'] as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<Uint8List?> fetchSignatureBytes(String url) async {
  if (url.isEmpty) return null;
  try {
    final res = await _pmesDio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = res.data;
    return bytes == null ? null : Uint8List.fromList(bytes);
  } catch (e) {
    throw parseError(e);
  }
}

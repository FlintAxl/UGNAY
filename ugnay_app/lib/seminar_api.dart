import 'api_client.dart';

String _s(Object? v) => (v ?? '').toString();
String? _o(Object? v) => v?.toString();
int _i(Object? v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
bool _b(Object? v) => v == true;

class PmesPreferenceApplicant {
  final String applicationId;
  final String? referenceNo;
  final String? userId;
  final String fullName;
  final String email;
  final String phone;
  final String status;

  const PmesPreferenceApplicant({
    required this.applicationId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.status,
    this.referenceNo,
    this.userId,
  });

  factory PmesPreferenceApplicant.fromJson(Map<String, dynamic> j) =>
      PmesPreferenceApplicant(
        applicationId: _s(j['application_id']),
        referenceNo: _o(j['reference_no']),
        userId: _o(j['user_id']),
        fullName: _s(j['full_name']),
        email: _s(j['email']),
        phone: _s(j['phone']),
        status: _s(j['status']),
      );
}

class PmesPreferenceDate {
  final String date;
  final String label;
  final int count;
  final bool isPast;
  final bool isMostPreferred;
  final List<PmesPreferenceApplicant> applicants;

  const PmesPreferenceDate({
    required this.date,
    required this.label,
    required this.count,
    required this.isPast,
    required this.isMostPreferred,
    required this.applicants,
  });

  factory PmesPreferenceDate.fromJson(Map<String, dynamic> j) =>
      PmesPreferenceDate(
        date: _s(j['date']),
        label: _s(j['label']),
        count: _i(j['count']),
        isPast: _b(j['is_past']),
        isMostPreferred: _b(j['is_most_preferred']),
        applicants: ((j['applicants'] as List?) ?? [])
            .map(
              (e) => PmesPreferenceApplicant.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
}

class PmesSeminarSummary {
  final String id;
  final String date;
  final String label;
  final String venue;
  final String status;
  final String phase;
  final int attending;
  final int notAttending;
  final int noResponse;
  final int total;
  final bool canRespond;
  final String? createdAt;

  const PmesSeminarSummary({
    required this.id,
    required this.date,
    required this.label,
    required this.venue,
    required this.status,
    required this.phase,
    this.attending = 0,
    this.notAttending = 0,
    this.noResponse = 0,
    this.total = 0,
    this.canRespond = false,
    this.createdAt,
  });

  factory PmesSeminarSummary.fromJson(Map<String, dynamic> j) =>
      PmesSeminarSummary(
        id: _s(j['id']),
        date: _s(j['date']),
        label: _s(j['label']),
        venue: _s(j['venue']),
        status: _s(j['status']),
        phase: _s(j['phase']),
        attending: _i(j['attending']),
        notAttending: _i(j['not_attending']),
        noResponse: _i(j['no_response']),
        total: _i(j['total']),
        canRespond: _b(j['can_respond']),
        createdAt: _o(j['created_at']),
      );
}

class SeminarParticipant {
  final String userId;
  final String fullName;
  final String email;
  final String phone;
  final String? respondedAt;

  const SeminarParticipant({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    this.respondedAt,
  });

  factory SeminarParticipant.fromJson(Map<String, dynamic> j) =>
      SeminarParticipant(
        userId: _s(j['user_id']),
        fullName: _s(j['full_name']),
        email: _s(j['email']),
        phone: _s(j['phone']),
        respondedAt: _o(j['responded_at']),
      );
}

class SeminarTotals {
  final int attending;
  final int notAttending;
  final int noResponse;
  final int total;

  const SeminarTotals({
    required this.attending,
    required this.notAttending,
    required this.noResponse,
    required this.total,
  });

  factory SeminarTotals.fromJson(Map<String, dynamic> j) => SeminarTotals(
    attending: _i(j['attending']),
    notAttending: _i(j['not_attending']),
    noResponse: _i(j['no_response']),
    total: _i(j['total']),
  );
}

class SeminarAttendance {
  final PmesSeminarSummary seminar;
  final SeminarTotals totals;
  final List<SeminarParticipant> attending;
  final List<SeminarParticipant> notAttending;
  final List<SeminarParticipant> noResponse;

  const SeminarAttendance({
    required this.seminar,
    required this.totals,
    required this.attending,
    required this.notAttending,
    required this.noResponse,
  });

  factory SeminarAttendance.fromJson(Map<String, dynamic> j) =>
      SeminarAttendance(
        seminar: PmesSeminarSummary.fromJson(
          Map<String, dynamic>.from((j['seminar'] as Map?) ?? {}),
        ),
        totals: SeminarTotals.fromJson(
          Map<String, dynamic>.from((j['totals'] as Map?) ?? {}),
        ),
        attending: _participants(j['attending']),
        notAttending: _participants(j['not_attending']),
        noResponse: _participants(j['no_response']),
      );

  static List<SeminarParticipant> _participants(Object? raw) =>
      ((raw as List?) ?? [])
          .map(
            (e) => SeminarParticipant.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
}

class MemberSeminar {
  final PmesSeminarSummary? seminar;
  final String? response;
  final String? respondedAt;
  final bool canRespond;

  const MemberSeminar({
    this.seminar,
    this.response,
    this.respondedAt,
    this.canRespond = false,
  });

  factory MemberSeminar.fromJson(Map<String, dynamic> j) {
    final raw = j['seminar'];
    final seminar = raw == null
        ? null
        : PmesSeminarSummary.fromJson(Map<String, dynamic>.from(raw as Map));
    return MemberSeminar(
      seminar: seminar,
      response: _o(j['response']),
      respondedAt: _o(j['responded_at']),
      canRespond: _b(j['can_respond']) || (seminar?.canRespond ?? false),
    );
  }
}

// ============================================================ API

Future<List<PmesPreferenceDate>> listPmesPreferences() async {
  try {
    final res = await dio.get('/admin/seminars/preferences');
    final data = Map<String, dynamic>.from(res.data as Map);
    return ((data['dates'] as List?) ?? [])
        .map(
          (e) =>
              PmesPreferenceDate.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  } catch (e) {
    throw parseError(e);
  }
}

Future<List<PmesSeminarSummary>> listSeminars() async {
  try {
    final res = await dio.get('/admin/seminars');
    return (res.data as List)
        .map(
          (e) =>
              PmesSeminarSummary.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  } catch (e) {
    throw parseError(e);
  }
}

Future<PmesSeminarSummary> scheduleSeminar(String date, {String? venue}) async {
  try {
    final res = await dio.post(
      '/admin/seminars',
      data: {
        'date': date,
        if (venue != null && venue.isNotEmpty) 'venue': venue,
      },
    );
    return PmesSeminarSummary.fromJson(
      Map<String, dynamic>.from(res.data as Map),
    );
  } catch (e) {
    throw parseError(e);
  }
}

Future<PmesSeminarSummary> cancelSeminar(String id, {String? reason}) async {
  try {
    final res = await dio.post(
      '/admin/seminars/$id/cancel',
      data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
    return PmesSeminarSummary.fromJson(
      Map<String, dynamic>.from(res.data as Map),
    );
  } catch (e) {
    throw parseError(e);
  }
}

Future<SeminarAttendance> getSeminarAttendance(String id) async {
  try {
    final res = await dio.get('/admin/seminars/$id/attendance');
    return SeminarAttendance.fromJson(
      Map<String, dynamic>.from(res.data as Map),
    );
  } catch (e) {
    throw parseError(e);
  }
}

Future<MemberSeminar> getMemberSeminar() async {
  try {
    final res = await dio.get('/member/seminars/current');
    return MemberSeminar.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<MemberSeminar> respondToSeminar(String id, String response) async {
  try {
    final res = await dio.put(
      '/member/seminars/$id/response',
      data: {'response': response},
    );
    return MemberSeminar.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

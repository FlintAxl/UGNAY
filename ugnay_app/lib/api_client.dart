import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'config.dart';
import 'storage.dart';

/// Error shape returned by the backend: {"detail": {"code", "message", ...}}
class ApiException implements Exception {
  final int? status;
  final String code;
  final String message;
  final String? reason;

  ApiException({this.status, required this.code, required this.message, this.reason});

  @override
  String toString() => message;
}

/// Set in main.dart. Called when the session can no longer be renewed.
void Function()? onSessionExpired;

// ------------------------------------------------------------ Dio + tokens

String? _errorCode(DioException e) {
  final data = e.response?.data;
  if (data is Map && data['detail'] is Map) {
    return (data['detail'] as Map)['code']?.toString();
  }
  return null;
}

Future<bool>? _refreshing;

/// Uses the refresh token to get a new access token. Concurrent callers share
/// one refresh request.
Future<bool> _refreshAccessToken() {
  _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  return _refreshing!;
}

Future<bool> _doRefresh() async {
  final refresh = await TokenStorage.refreshToken();
  if (refresh == null) return false;
  try {
    // Plain Dio without interceptors, so a failure can't loop.
    final plain = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    final res = await plain.post('/auth/refresh', data: {'refresh_token': refresh});
    await TokenStorage.saveAccessToken(res.data['access_token'] as String);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _expireSession() async {
  await TokenStorage.clear();
  onSessionExpired?.call();
}

Dio _createDio() {
  final d = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    // Face processing can be slow, especially the first request after startup.
    sendTimeout: const Duration(seconds: 90),
    receiveTimeout: const Duration(seconds: 90),
  ));

  d.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      // Attach the access token to everything except the /auth/* endpoints.
      if (!options.path.startsWith('/auth/')) {
        final token = await TokenStorage.accessToken();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (err, handler) async {
      final req = err.requestOptions;
      final isAuthPath = req.path.startsWith('/auth/');
      final code = _errorCode(err);

      if (err.response?.statusCode == 401 && !isAuthPath) {
        if (code == 'TOKEN_EXPIRED' && req.extra['retried'] != true) {
          if (await _refreshAccessToken()) {
            req.extra['retried'] = true;
            final token = await TokenStorage.accessToken();
            req.headers['Authorization'] = 'Bearer $token';
            try {
              return handler.resolve(await d.fetch(req));
            } on DioException catch (e) {
              return handler.next(e);
            }
          }
          await _expireSession();
        } else if (code == 'INVALID_TOKEN') {
          // e.g. the account was suspended or the token is bad.
          await _expireSession();
        }
      }
      handler.next(err);
    },
  ));
  return d;
}

final Dio dio = _createDio();

ApiException parseError(Object e) {
  if (e is DioException) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return ApiException(
        code: 'NETWORK',
        message: 'Cannot reach the server. Check your connection and that the backend is running.',
      );
    }
    if (e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiException(
        code: 'TIMEOUT',
        message: 'The server took too long to respond. Please try again.',
      );
    }
    final data = e.response?.data;
    if (data is Map && data['detail'] is Map) {
      final d = data['detail'] as Map;
      return ApiException(
        status: e.response?.statusCode,
        code: d['code']?.toString() ?? 'ERROR',
        message: d['message']?.toString() ?? 'Something went wrong.',
        reason: d['reason']?.toString(),
      );
    }
    if (data is Map && data['detail'] is List && (data['detail'] as List).isNotEmpty) {
      final first = (data['detail'] as List).first;
      final msg = first is Map ? first['msg']?.toString() : null;
      return ApiException(
        status: e.response?.statusCode,
        code: 'VALIDATION',
        message: 'Please check your inputs${msg != null ? ': $msg' : '.'}',
      );
    }
    return ApiException(
      status: e.response?.statusCode,
      code: 'UNKNOWN',
      message: 'Unexpected server response (${e.response?.statusCode ?? 'no status'}).',
    );
  }
  return ApiException(code: 'UNKNOWN', message: e.toString());
}

// ---------------------------------------------------------------- Register

Future<String> registerUser({
  required String fullName,
  required String email,
  required String phone,
  required String address,
  required String password,
  required Uint8List idPhoto,
  required Uint8List facePhoto,
}) async {
  final form = FormData.fromMap({
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'address': address,
    'password': password,
    'id_photo': MultipartFile.fromBytes(idPhoto, filename: 'id.jpg'),
    'face_photo': MultipartFile.fromBytes(facePhoto, filename: 'face.jpg'),
  });
  try {
    final res = await dio.post('/auth/register', data: form);
    return (res.data['message'] ?? 'Registration submitted.').toString();
  } catch (e) {
    throw parseError(e);
  }
}

// ------------------------------------------------------------------- Login

/// Step 1: email + password. Returns a short-lived face_token.
/// Throws ApiException with code ACCOUNT_PENDING / ACCOUNT_REJECTED /
/// ACCOUNT_SUSPENDED / INVALID_CREDENTIALS.
Future<String> login(String email, String password) async {
  try {
    final res = await dio.post('/auth/login', data: {'email': email, 'password': password});
    return res.data['face_token'] as String;
  } catch (e) {
    throw parseError(e);
  }
}

/// Step 2: live face photo + face_token. Returns the real session tokens.
Future<AuthSession> verifyFace({
  required String faceToken,
  required Uint8List image,
}) async {
  final form = FormData.fromMap({
    'face_token': faceToken,
    'image': MultipartFile.fromBytes(image, filename: 'face.jpg'),
  });
  try {
    final res = await dio.post('/auth/verify-face', data: form);
    final d = res.data as Map;
    return AuthSession(
      accessToken: d['access_token'] as String,
      refreshToken: d['refresh_token'] as String,
      role: d['role'] as String,
      fullName: d['full_name'] as String,
    );
  } catch (e) {
    throw parseError(e);
  }
}

// ------------------------------------------------------------------- Admin

class Applicant {
  final String id;
  final String email;
  final String fullName;
  final String phone;
  final String status;
  final String role;
  final String createdAt;
  final String? address;
  final String? idPhotoUrl;
  final String? facePhotoUrl;
  final String? rejectionReason;

  const Applicant({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phone,
    required this.status,
    required this.role,
    required this.createdAt,
    this.address,
    this.idPhotoUrl,
    this.facePhotoUrl,
    this.rejectionReason,
  });

  factory Applicant.fromJson(Map<String, dynamic> j) => Applicant(
        id: j['id'] as String,
        email: j['email'] as String,
        fullName: j['full_name'] as String,
        phone: (j['phone'] ?? '').toString(),
        status: j['status'] as String,
        role: j['role'] as String,
        createdAt: (j['created_at'] ?? '').toString(),
        address: j['address'] as String?,
        idPhotoUrl: j['id_photo_url'] as String?,
        facePhotoUrl: j['face_photo_url'] as String?,
        rejectionReason: j['rejection_reason'] as String?,
      );
}

Future<List<Applicant>> listApplicants(String status) async {
  try {
    final res = await dio.get('/admin/applicants', queryParameters: {'status': status});
    return (res.data as List)
        .map((e) => Applicant.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (e) {
    throw parseError(e);
  }
}

Future<Applicant> getApplicant(String id) async {
  try {
    final res = await dio.get('/admin/applicants/$id');
    return Applicant.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    throw parseError(e);
  }
}

Future<void> approveApplicant(String id, String role) async {
  try {
    await dio.post('/admin/applicants/$id/approve', data: {'role': role});
  } catch (e) {
    throw parseError(e);
  }
}

Future<void> rejectApplicant(String id, String reason) async {
  try {
    await dio.post('/admin/applicants/$id/reject', data: {'reason': reason});
  } catch (e) {
    throw parseError(e);
  }
}
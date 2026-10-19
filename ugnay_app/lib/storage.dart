import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthSession {
  final String accessToken;
  final String refreshToken;
  final String role;
  final String fullName;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.role,
    required this.fullName,
  });
}

/// Keeps JWTs in the platform's secure storage (Keystore on Android).
class TokenStorage {
  static const _storage = FlutterSecureStorage();

  static Future<void> save(AuthSession s) async {
    await _storage.write(key: 'access_token', value: s.accessToken);
    await _storage.write(key: 'refresh_token', value: s.refreshToken);
    await _storage.write(key: 'role', value: s.role);
    await _storage.write(key: 'full_name', value: s.fullName);
  }

  static Future<String?> accessToken() => _storage.read(key: 'access_token');
  static Future<String?> refreshToken() => _storage.read(key: 'refresh_token');

  static Future<void> saveAccessToken(String token) =>
      _storage.write(key: 'access_token', value: token);

  static Future<void> clear() => _storage.deleteAll();
}
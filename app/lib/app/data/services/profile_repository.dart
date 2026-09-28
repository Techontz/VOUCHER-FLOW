import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../models/profile_models.dart';
import 'api_service.dart';

/// The signed-in user's own profile, signature, password and sessions.
class ProfileRepository {
  ProfileRepository(this._api);

  final ApiService _api;

  /// The shared instance, registered on first use.
  static ProfileRepository get to => Get.isRegistered<ProfileRepository>()
      ? Get.find<ProfileRepository>()
      : Get.put(ProfileRepository(Get.find<ApiService>()), permanent: true);

  /// Name, phone and job title; with [avatar], sent as multipart with the
  /// photo (the web's FormData branch).
  Future<void> updateProfile({
    required String name,
    required String phone,
    required String jobTitle,
    ({Uint8List bytes, String filename})? avatar,
  }) async {
    final fields = {'name': name, 'phone': phone, 'job_title': jobTitle};
    if (avatar == null) {
      await _api.put('/profile', fields);
      return;
    }
    await _api.upload('/profile', [
      http.MultipartFile.fromBytes(
        'avatar',
        avatar.bytes,
        filename: avatar.filename,
      ),
    ], fields: fields);
  }

  /// The user as `/auth/me` returns it — for fields the shared user model
  /// does not carry (when the signature was last updated).
  Future<Map<String, dynamic>> me() async {
    final payload = await _api.get('/auth/me') as Map;
    final user = payload['user'];
    return user is Map ? Map<String, dynamic>.from(user) : const {};
  }

  Future<String?> savedSignature() async {
    final payload = await _api.get('/profile/signature') as Map;
    final value = payload['signature'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// Saves a `data:image/…;base64,` signature; returns when it was stored.
  Future<DateTime?> storeSignature(String dataUrl) async {
    final payload = await _api.post('/profile/signature', {
      'signature': dataUrl,
    });
    return payload is Map
        ? DateTime.tryParse('${payload['updated_at'] ?? ''}')?.toLocal()
        : null;
  }

  Future<void> removeSignature() => _api.delete('/profile/signature');

  Future<void> changePassword({
    required String current,
    required String password,
    required String confirmation,
  }) => _api.post('/auth/change-password', {
    'current_password': current,
    'password': password,
    'password_confirmation': confirmation,
  });

  Future<List<ProfileSession>> sessions() async {
    final payload = await _api.get('/auth/sessions') as Map;
    return (payload['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => ProfileSession.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> revokeSession(int id) => _api.delete('/auth/sessions/$id');

  Future<void> logoutAll() => _api.post('/auth/logout-all');
}

import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'api_service.dart';

/// A logo held on the device until it can be uploaded.
class PickedLogo {
  const PickedLogo({required this.bytes, required this.name, required this.mime});

  final Uint8List bytes;
  final String name;

  /// image/png, image/jpeg or image/webp.
  final String mime;

  int get size => bytes.length;

  http.MultipartFile part(String field) => http.MultipartFile.fromBytes(field, bytes, filename: name);
}

/// A workflow preset offered during onboarding (GET /workflows/presets).
class WorkflowPreset {
  WorkflowPreset.fromJson(Map<String, dynamic> j)
    : key = '${j['key']}',
      name = '${j['name'] ?? j['key']}',
      description = '${j['description'] ?? ''}';

  final String key, name, description;
}

/// The answer to POST /auth/register: a signed-in administrator, their new
/// company, and where the registration code went.
class Registration {
  Registration(this.raw)
    : company = Company.fromJson(Map<String, dynamic>.from(raw['company'] as Map)),
      otpIdentifier = '${(raw['otp'] as Map?)?['identifier'] ?? (raw['user'] as Map?)?['email'] ?? ''}',
      // An API that cannot deliver e-mail registers without the code step.
      requiresVerification = raw['requires_verification'] != false;

  /// The whole payload (token, user, company), for starting the session.
  final Map<String, dynamic> raw;
  final Company company;
  final String otpIdentifier;
  final bool requiresVerification;
}

/// Every call the public auth screens make that the session does not:
/// registration and what follows it, account codes, password reset and the
/// onboarding steps — the same endpoints the website uses.
class AuthRepository {
  AuthRepository(this._api);
  final ApiService _api;

  static AuthRepository get to => Get.isRegistered<AuthRepository>()
      ? Get.find<AuthRepository>()
      : Get.put(AuthRepository(Get.find<ApiService>()), permanent: true);

  // ── public ──

  /// The public plans, in their display order.
  Future<List<Plan>> plans() async {
    final j = Map<String, dynamic>.from(await _api.get('/plans') as Map);
    return [
      for (final p in (j['data'] as List? ?? const []))
        if ((p as Map)['is_public'] != false) Plan.fromJson(Map<String, dynamic>.from(p)),
    ];
  }

  /// POST /auth/register. Only fields the endpoint accepts are sent.
  Future<Registration> register(Map<String, dynamic> body) async =>
      Registration(Map<String, dynamic>.from(await _api.post('/auth/register', body) as Map));

  /// POST /auth/otp/send — (re)sends a registration code.
  Future<void> sendOtp(String identifier, String purpose) =>
      _api.post('/auth/otp/send', {'identifier': identifier, 'purpose': purpose});

  /// POST /auth/otp/verify — confirms the administrator's email.
  Future<void> verifyOtp(String identifier, String code, String purpose) =>
      _api.post('/auth/otp/verify', {'identifier': identifier, 'code': code, 'purpose': purpose});

  /// POST /auth/forgot-password — answers the same whether or not the
  /// address has an account.
  Future<void> forgotPassword(String email) => _api.post('/auth/forgot-password', {'email': email});

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
    required String confirmation,
  }) => _api.post('/auth/reset-password', {
    'email': email,
    'code': code,
    'password': password,
    'password_confirmation': confirmation,
  });

  // ── as the new administrator ──

  /// PUT /company — the same endpoint Settings uses.
  Future<void> updateCompany(Map<String, dynamic> fields) => _api.put('/company', fields);

  /// POST /company/logo — the same validated upload Branding uses.
  Future<void> uploadLogo(PickedLogo logo) => _api.upload('/company/logo', [logo.part('logo')]);

  /// POST /company/branding — the colour, and the logo when one was chosen.
  Future<void> updateBranding({required String primaryColor, PickedLogo? logo}) => _api.upload(
    '/company/branding',
    [if (logo != null) logo.part('logo')],
    fields: {'primary_color': primaryColor},
  );

  Future<List<WorkflowPreset>> workflowPresets() async {
    final j = Map<String, dynamic>.from(await _api.get('/workflows/presets') as Map);
    return [for (final p in (j['data'] as List? ?? const [])) WorkflowPreset.fromJson(Map<String, dynamic>.from(p as Map))];
  }

  Future<void> applyWorkflowPreset(String preset) => _api.post('/workflows/apply-preset', {'preset': preset});

  /// The names of the company's departments.
  Future<List<String>> departmentNames() async {
    final j = await _api.get('/departments');
    final list = j is Map ? (j['data'] as List? ?? const []) : (j as List? ?? const []);
    return [for (final d in list) '${(d as Map)['name']}'];
  }

  Future<void> createDepartment(String name) => _api.post('/departments', {'name': name});

  Future<void> inviteEmployee({required String name, required String email, required String role}) =>
      _api.post('/employees', {'name': name, 'email': email, 'role': role, 'send_invitation': true});

  Future<void> subscribe(int planId) => _api.post('/billing/subscribe', {'plan_id': planId});
}

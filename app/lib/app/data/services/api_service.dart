import 'dart:convert';

import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config.dart';

/// A failed request, carrying Laravel's per-field validation messages.
class ApiException implements Exception {
  ApiException(
    this.statusCode,
    this.message, [
    this.errors = const {},
    this.code,
  ]);

  final int statusCode;
  final String message;
  final Map<String, List<String>> errors;
  final String? code;

  String? field(String name) => errors[name]?.first;

  bool get isUnauthorised => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isSubscriptionLapsed => statusCode == 402;

  @override
  String toString() => message;
}

/// Talks to the Laravel API and owns the Sanctum token.
class ApiService extends GetxService {
  static const _tokenKey = 'vouchflow.token';
  static const _localeKey = 'vouchflow.locale';

  late final SharedPreferences _prefs;
  final _client = http.Client();

  String? _token;
  String _locale = 'en';

  /// Raised when the server rejects the stored token, so the app can sign out.
  final onUnauthorised = <void Function()>[];

  Future<ApiService> init() async {
    _prefs = await SharedPreferences.getInstance();
    _token = _prefs.getString(_tokenKey);
    _locale = _prefs.getString(_localeKey) ?? 'en';
    return this;
  }

  String? get token => _token;
  bool get hasToken => _token != null && _token!.isNotEmpty;
  String get locale => _locale;

  Future<void> setToken(String? value) async {
    _token = value;
    if (value == null) {
      await _prefs.remove(_tokenKey);
    } else {
      await _prefs.setString(_tokenKey, value);
    }
  }

  Future<void> setLocale(String value) async {
    _locale = value;
    await _prefs.setString(_localeKey, value);
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('${VfConfig.apiUrl}$path');
    if (query == null || query.isEmpty) return base;

    final params = <String, String>{};
    query.forEach((key, value) {
      if (value != null && '$value'.isNotEmpty) params[key] = '$value';
    });
    return base.replace(queryParameters: {...base.queryParameters, ...params});
  }

  Map<String, String> _headers({bool json = true}) => {
    'Accept': 'application/json',
    'X-Locale': _locale,
    if (json) 'Content-Type': 'application/json',
    if (hasToken) 'Authorization': 'Bearer $_token',
  };

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) => _send(
    () => _client.get(_uri(path, query), headers: _headers(json: false)),
  );

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) => _send(
    () => _client.post(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body ?? {}),
    ),
  );

  Future<dynamic> put(String path, [Map<String, dynamic>? body]) => _send(
    () => _client.put(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body ?? {}),
    ),
  );

  Future<dynamic> delete(String path) =>
      _send(() => _client.delete(_uri(path), headers: _headers()));

  /// Multipart upload — used for attachments, avatars and the company logo.
  Future<dynamic> upload(
    String path,
    List<http.MultipartFile> files, {
    Map<String, String> fields = const {},
    String method = 'POST',
  }) async {
    final request = http.MultipartRequest(method, _uri(path))
      ..headers.addAll(_headers(json: false))
      ..fields.addAll(fields)
      ..files.addAll(files);

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _handle(response);
  }

  /// Raw bytes, for PDFs and attachments.
  Future<List<int>> bytes(String path, [Map<String, dynamic>? query]) async {
    final response = await _client.get(
      _uri(path, query),
      headers: {
        'Accept': 'application/octet-stream',
        'X-Locale': _locale,
        if (hasToken) 'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode >= 400) {
      _handle(response);
    }
    return response.bodyBytes;
  }

  Future<dynamic> _send(Future<http.Response> Function() run) async {
    try {
      return _handle(await run());
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(
        0,
        'Cannot reach the server. Check your connection and try again.',
      );
    }
  }

  dynamic _handle(http.Response response) {
    dynamic payload;
    if (response.body.isNotEmpty) {
      try {
        payload = jsonDecode(response.body);
      } catch (_) {
        payload = {'message': response.body};
      }
    }

    if (response.statusCode >= 400) {
      final map = payload is Map<String, dynamic>
          ? payload
          : <String, dynamic>{};

      final errors = <String, List<String>>{};
      final raw = map['errors'];
      if (raw is Map) {
        raw.forEach((key, value) {
          errors['$key'] = (value as List).map((e) => '$e').toList();
        });
      }

      if (response.statusCode == 401) {
        for (final handler in onUnauthorised) {
          handler();
        }
      }

      throw ApiException(
        response.statusCode,
        (map['message'] as String?) ??
            'Request failed (${response.statusCode})',
        errors,
        map['code'] as String?,
      );
    }

    return payload;
  }

  @override
  void onClose() {
    _client.close();
    super.onClose();
  }
}

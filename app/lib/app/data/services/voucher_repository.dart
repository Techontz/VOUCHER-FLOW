import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'api_service.dart';

/// Every voucher-related call the app makes, in one place.
class VoucherRepository {
  VoucherRepository(this._api);

  final ApiService _api;

  List<T> _list<T>(dynamic payload, T Function(Map<String, dynamic>) build) =>
      ((payload as Map<String, dynamic>)['data'] as List)
          .map((e) => build(e as Map<String, dynamic>))
          .toList();

  Future<DashboardData> dashboard() async => DashboardData.fromJson(
    await _api.get('/dashboard') as Map<String, dynamic>,
  );

  Future<List<Voucher>> list({
    String? status,
    String? query,
    String scope = 'all',
    int page = 1,
  }) async {
    final payload = await _api.get('/vouchers', {
      'status': status,
      'q': query,
      'scope': scope,
      'page': page,
      'per_page': 25,
    });
    return _list(payload, Voucher.fromJson);
  }

  Future<List<Voucher>> pending() async =>
      _list(await _api.get('/vouchers/pending'), Voucher.fromJson);

  Future<Voucher> show(int id) async {
    final payload = await _api.get('/vouchers/$id') as Map<String, dynamic>;
    return Voucher.fromJson(payload['data'] as Map<String, dynamic>);
  }

  Future<Voucher> create(Map<String, dynamic> body) async {
    final payload = await _api.post('/vouchers', body) as Map<String, dynamic>;
    return Voucher.fromJson(payload['data'] as Map<String, dynamic>);
  }

  Future<Voucher> update(int id, Map<String, dynamic> body) async {
    final payload =
        await _api.put('/vouchers/$id', body) as Map<String, dynamic>;
    return Voucher.fromJson(payload['data'] as Map<String, dynamic>);
  }

  /// Workflow transitions. The API decides what is permitted; the app only asks.
  Future<Voucher> act(
    int id,
    String action, {
    Map<String, dynamic> body = const {},
  }) async {
    final payload =
        await _api.post('/vouchers/$id/$action', body) as Map<String, dynamic>;
    return Voucher.fromJson(payload['data'] as Map<String, dynamic>);
  }

  Future<Voucher> submit(int id, {String? comment}) =>
      act(id, 'submit', body: {'comment': comment});

  Future<Voucher> sign(
    int id, {
    String? signature,
    String? comment,
    bool save = true,
  }) => act(
    id,
    'sign',
    body: {
      'signature': signature,
      'comment': comment,
      'save_signature': save && signature != null,
      'use_saved_signature': signature == null,
    },
  );

  Future<Voucher> submitSigned(int id, {String? comment}) =>
      act(id, 'submit-signed', body: {'comment': comment});

  Future<Voucher> approve(int id, {String? comment, String? signature}) =>
      act(id, 'approve', body: {'comment': comment, 'signature': signature});

  Future<Voucher> reject(int id, String comment) =>
      act(id, 'reject', body: {'comment': comment});

  Future<Voucher> requestChanges(int id, String comment) =>
      act(id, 'request-changes', body: {'comment': comment});

  /// Releases the funds and records the reference against the voucher.
  /// Records the release of money.
  ///
  /// The two formats settle differently: a transfer is reconciled against its
  /// reference, cash is acknowledged by whoever took it. Each sends only what
  /// it has, which is exactly what the API requires of it.
  Future<Voucher> pay(
    int id, {
    required bool isCash,
    required String method,
    String? reference,
    String? receivedBy,
    String? comment,
  }) => act(
    id,
    'pay',
    body: {
      'payment_method': method,
      if (isCash) 'received_by': receivedBy,
      if (!isCash) 'payment_reference': reference,
      if (!isCash && method.toLowerCase().contains('cheque'))
        'cheque_number': reference,
      'note': comment,
    },
  );

  Future<void> comment(int id, String body) =>
      _api.post('/vouchers/$id/comments', {'body': body});

  Future<void> attach(int id, List<http.MultipartFile> files) =>
      _api.upload('/vouchers/$id/attachments', files);

  Future<Uint8List> pdf(int id, {bool download = false}) async =>
      Uint8List.fromList(
        await _api.bytes('/vouchers/$id/pdf${download ? '/download' : ''}'),
      );

  Future<List<VoucherType>> types() async =>
      _list(await _api.get('/voucher-types'), VoucherType.fromJson);

  Future<List<Department>> departments() async =>
      _list(await _api.get('/departments'), Department.fromJson);

  Future<List<AppNotificationItem>> notifications() async => _list(
    await _api.get('/notifications', {'per_page': 50}),
    AppNotificationItem.fromJson,
  );

  Future<void> markNotificationRead(int id) =>
      _api.post('/notifications/$id/read');

  Future<int> markAllNotificationsRead() async {
    final payload =
        await _api.post('/notifications/read-all') as Map<String, dynamic>;
    return (payload['count'] as num?)?.toInt() ?? 0;
  }

  Future<String?> savedSignature() async {
    final payload =
        await _api.get('/profile/signature') as Map<String, dynamic>;
    return payload['signature'] as String?;
  }

  Future<void> storeSignature(String dataUrl) =>
      _api.post('/profile/signature', {'signature': dataUrl});

  Future<void> changePassword(String current, String next, String confirm) =>
      _api.post('/auth/change-password', {
        'current_password': current,
        'password': next,
        'password_confirmation': confirm,
      });

  /// Encodes raw PNG bytes as the data URL the API stores for signatures.
  static String encodeSignature(Uint8List png) =>
      'data:image/png;base64,${base64Encode(png)}';
}

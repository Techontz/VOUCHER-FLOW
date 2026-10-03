import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/detail_models.dart';
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

  /// Approves several reviewed vouchers in one go; each goes through the same
  /// server-side approval as a single one. Returns what was approved and skipped.
  Future<Map<String, dynamic>> bulkApprove(
    List<int> ids, {
    String? comment,
  }) async => Map<String, dynamic>.from(
    await _api.post('/vouchers/bulk-approve', {
          'ids': ids,
          'comment': comment,
          'confirm': true,
        })
        as Map,
  );

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
    String? receiverIdNumber,
    String? comment,
    double? amount,
  }) => act(
    id,
    'pay',
    body: {
      'payment_method': method,
      // Left out, the server pays the whole balance; less pays part now.
      'amount': ?amount,
      if (isCash) 'received_by': receivedBy,
      if (isCash && (receiverIdNumber ?? '').isNotEmpty)
        'receiver_id_number': receiverIdNumber,
      if (!isCash) 'payment_reference': reference,
      if (!isCash && method.toLowerCase().contains('cheque'))
        'cheque_number': reference,
      'note': comment,
    },
  );

  /// Withdraws a submitted voucher (the requester's own, before a decision).
  Future<Voucher> cancel(int id, {String? comment}) =>
      act(id, 'cancel', body: {'comment': comment});

  /// Deletes a draft for good.
  Future<void> delete(int id) => _api.delete('/vouchers/$id');

  /// One page of the register, with the list's totals — for the payment queue.
  Future<VoucherPage> page({
    String? status,
    String? kind,
    int page = 1,
    int perPage = 20,
    String? paidFrom,
    String? paidTo,
  }) async => VoucherPage.fromJson(
    Map<String, dynamic>.from(
      await _api.get('/vouchers', {
            'status': ?status,
            if ((kind ?? '').isNotEmpty) 'kind': kind,
            'page': page,
            'per_page': perPage,
            'paid_from': ?paidFrom,
            'paid_to': ?paidTo,
          })
          as Map,
    ),
  );

  /// The company's approval routes, for the progress line on queue rows.
  Future<List<WorkflowInfo>> workflows() async =>
      _list(await _api.get('/workflows'), WorkflowInfo.fromJson);

  /// Approves several vouchers, typed.
  Future<BulkApproveResult> bulkApproveVouchers(
    List<int> ids, {
    String? comment,
  }) async => BulkApproveResult.fromJson(await bulkApprove(ids, comment: comment));

  /// A stored attachment or filed acknowledgement, as bytes.
  Future<Uint8List> attachmentBytes(int id, int attachmentId) async =>
      Uint8List.fromList(await _api.bytes('/vouchers/$id/attachments/$attachmentId'));

  /// A report export (pdf, xlsx or csv) built by the server.
  Future<Uint8List> exportReport(
    String kind,
    Map<String, dynamic> params,
    String format,
  ) async => Uint8List.fromList(
    await _api.bytes('/reports/$kind/export', {...params, 'format': format}),
  );

  Future<void> comment(int id, String body) =>
      _api.post('/vouchers/$id/comments', {'body': body});

  Future<void> attach(int id, List<http.MultipartFile> files) =>
      _api.upload('/vouchers/$id/attachments', files);

  /// The printable cash acknowledgement for one payment, as PDF bytes.
  Future<Uint8List> acknowledgementPdf(
    int id,
    int paymentId, {
    String? lang,
  }) async => Uint8List.fromList(
    await _api.bytes('/vouchers/$id/payments/$paymentId/acknowledgement', {
      'lang': ?lang,
    }),
  );

  /// Files the receiver's signed copy against its payment. Field name `file`.
  Future<Voucher> uploadAcknowledgement(
    int id,
    int paymentId,
    http.MultipartFile file,
  ) async {
    final payload = await _api.upload(
      '/vouchers/$id/payments/$paymentId/acknowledgement',
      [file],
    );
    return Voucher.fromJson(
      (payload as Map<String, dynamic>)['data'] as Map<String, dynamic>,
    );
  }

  /// The voucher as the server renders it in the company's design — the same
  /// HTML the website shows (logo, stamps and the PAID / REJECTED mark).
  Future<String> documentHtml(int id) async {
    final payload = await _api.get('/vouchers/$id/document');
    final html = payload is Map ? payload['html'] : null;
    if (html is! String || html.isEmpty) {
      throw ApiException(500, 'No document.');
    }
    return html;
  }

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

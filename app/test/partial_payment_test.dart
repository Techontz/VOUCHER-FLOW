// Partial payments and cash acknowledgements, against the Phase 1 mock.
//
// A voucher approved for an amount may be paid part now and the balance
// later. Each release is its own payment record; the voucher stays approved
// (shown as partially paid) until the balance is cleared.

import 'package:flutter_test/flutter_test.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/models/models.dart';
import 'package:vouchflow/app/data/services/api_service.dart';

import 'support/mock_sign_in.dart';

void main() {
  late MockApi api;

  Future<Map<String, dynamic>> signIn(String email) => mockSignIn(api, email);

  Future<Map<String, dynamic>> show(int id) async =>
      (await api.handle('GET', '/vouchers/$id'))['data']
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> act(
    int id,
    String action, [
    Map<String, dynamic> body = const {},
  ]) async =>
      (await api.handle('POST', '/vouchers/$id/$action', body: body))['data']
          as Map<String, dynamic>;

  /// Raises a cash voucher and takes it through to approval.
  Future<int> approvedCashVoucher(double amount) async {
    await signIn('frank@watercom.test');
    final created =
        (await api.handle(
              'POST',
              '/vouchers',
              body: {
                'kind': 'cash',
                'voucher_type_id': 102,
                'department_id': 2,
                'payee': 'Kariakoo Stationers',
                'purpose': 'Branch stationery restock',
                'amount': amount,
                'payment_method': 'Cash',
              },
            ))['data']
            as Map<String, dynamic>;
    final id = created['id'] as int;
    await act(id, 'submit');

    await signIn('joseph@watercom.test');
    await act(id, 'sign', {'use_saved_signature': true});
    await act(id, 'submit-signed');

    await signIn('emmanuel@watercom.test');
    final approved = await act(id, 'approve');
    expect(approved['status'], 'approved');
    return id;
  }

  setUp(() => api = MockApi());

  test('a voucher is paid in two parts, then closes as paid', () async {
    final id = await approvedCashVoucher(412500);

    await signIn('mwajuma@watercom.test');

    // More than the balance is refused.
    await expectLater(
      act(id, 'pay', {
        'payment_method': 'Cash — office float',
        'received_by': 'Asha Mushi',
        'amount': 500000,
      }),
      throwsA(isA<ApiException>()),
    );

    // Part now.
    var voucher = await act(id, 'pay', {
      'payment_method': 'Cash — office float',
      'received_by': 'Asha Mushi',
      'receiver_id_number': 'EMP-0042',
      'amount': 400000,
    });
    expect(voucher['status'], 'approved');
    expect(voucher['status_key'], 'partially_paid');
    expect(voucher['is_partially_paid'], isTrue);
    expect(voucher['amount_paid'], 400000);
    expect(voucher['balance'], 12500);
    expect(voucher['balance_text'], 'TZS 12,500');
    expect(
      (voucher['actions'] as Map)['pay'],
      isTrue,
      reason: 'the balance is still the cashier\'s to pay',
    );

    var model = Voucher.fromJson(voucher);
    expect(model.isPartiallyPaid, isTrue);
    expect(model.displayTag, 'tag-warn');
    expect(model.payments, hasLength(1));
    expect(model.payments.single.amount, 400000);
    expect(model.payments.single.balanceAfter, 12500);
    expect(model.payments.single.receiverIdNumber, 'EMP-0042');
    expect(model.payments.single.isAcknowledged, isFalse);

    // The printable acknowledgement needs the live server.
    await expectLater(
      api.handle(
        'GET',
        '/vouchers/$id/payments/${model.payments.single.id}/acknowledgement',
      ),
      throwsA(isA<ApiException>()),
    );

    // The signed copy is filed against its payment.
    voucher =
        (await api.handle(
              'POST',
              '/vouchers/$id/payments/${model.payments.single.id}/acknowledgement',
            ))['data']
            as Map<String, dynamic>;
    model = Voucher.fromJson(voucher);
    expect(model.payments.single.isAcknowledged, isTrue);
    final filed = model.attachments.where((a) => a.isAcknowledgement);
    expect(filed, hasLength(1));
    expect(filed.single.voucherPaymentId, model.payments.single.id);

    // The balance, with no amount named: the server pays what is left.
    voucher = await act(id, 'pay', {
      'payment_method': 'Cash — office float',
      'received_by': 'Asha Mushi',
    });
    expect(voucher['status'], 'paid');
    expect(voucher['status_key'], 'paid');
    expect(voucher['is_partially_paid'], isFalse);
    expect(voucher['balance'], 0);

    model = Voucher.fromJson(await show(id));
    expect(model.payments, hasLength(2));
    expect(model.payments.map((p) => p.amount), [400000, 12500]);
    expect(model.payments.last.balanceAfter, 0);
    expect(model.actions.pay, isFalse);
  });

  test('only a permitted user may file an acknowledgement', () async {
    final id = await approvedCashVoucher(412500);
    await signIn('mwajuma@watercom.test');
    final voucher = Voucher.fromJson(
      await act(id, 'pay', {
        'payment_method': 'Cash — office float',
        'received_by': 'Asha Mushi',
        'amount': 100000,
      }),
    );

    await signIn('frank@watercom.test');
    await expectLater(
      api.handle(
        'POST',
        '/vouchers/$id/payments/${voucher.payments.single.id}/acknowledgement',
      ),
      throwsA(
        isA<ApiException>().having((e) => e.isForbidden, 'forbidden', true),
      ),
    );
  });
}

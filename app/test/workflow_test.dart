// The approval workflow, exercised directly against the Phase 1 mock.
//
// These are the rules the client cares about: an employee sees only their own
// vouchers, the HOD signs but never approves, the CEO's decision is final, and
// only the cashier's step releases money.

import 'package:flutter_test/flutter_test.dart';
import 'package:vouchflow/app/data/mock/mock_api.dart';
import 'package:vouchflow/app/data/services/api_service.dart';

void main() {
  late MockApi api;

  Future<Map<String, dynamic>> signIn(String email) async =>
      await api.handle(
            'POST',
            '/auth/login',
            body: {'email': email, 'password': 'Password123!'},
          )
          as Map<String, dynamic>;

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

  setUp(() => api = MockApi());

  test('rejects the wrong password', () async {
    await expectLater(
      api.handle(
        'POST',
        '/auth/login',
        body: {'email': 'frank@watercom.test', 'password': 'wrong'},
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('a full voucher runs employee → HOD → CEO → cashier', () async {
    // 1. The employee raises a cash voucher and submits it.
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
                'amount': 412500,
                'payment_method': 'Cash',
              },
            ))['data']
            as Map<String, dynamic>;

    final id = created['id'] as int;
    expect(created['status'], 'draft');
    expect(created['kind'], 'cash');
    expect(created['number'], startsWith('PC-'));

    var voucher = await act(id, 'submit');
    expect(voucher['status'], 'in_review');
    expect(voucher['status_label'], 'Awaiting HOD signature');

    // 2. The head of the requesting department signs. Procurement is Peter's.
    await signIn('rehema@watercom.test');
    await expectLater(
      show(id),
      throwsA(
        isA<ApiException>().having((e) => e.isForbidden, 'forbidden', true),
      ),
      reason: 'a head of another department must not reach this voucher',
    );

    await signIn('joseph@watercom.test');
    voucher = await show(id);
    final hodActions = voucher['actions'] as Map<String, dynamic>;
    expect(hodActions['sign'], isTrue);
    expect(
      hodActions['approve'],
      isFalse,
      reason: 'the HOD step signs only — it never approves',
    );

    voucher = await act(id, 'sign', {'use_saved_signature': true});
    expect(voucher['status_label'], 'Signed — ready to submit');
    expect((voucher['actions'] as Map)['submit_signed'], isTrue);

    voucher = await act(id, 'submit-signed');
    expect(voucher['status_label'], 'Awaiting CEO approval');

    // 3. The CEO approves. The voucher is now the cashier's problem.
    await signIn('emmanuel@watercom.test');
    voucher = await show(id);
    expect((voucher['actions'] as Map)['approve'], isTrue);
    expect(
      (voucher['actions'] as Map)['pay'],
      isFalse,
      reason: 'approving and paying are separate steps',
    );

    voucher = await act(id, 'approve');
    expect(voucher['status'], 'approved');
    expect(voucher['status_label'], 'Approved — awaiting payment');

    // 4. The cashier releases the funds.
    await signIn('mwajuma@watercom.test');
    voucher = await show(id);
    expect((voucher['actions'] as Map)['pay'], isTrue);
    expect((voucher['actions'] as Map)['approve'], isFalse);

    await expectLater(
      act(id, 'pay', const {}),
      throwsA(isA<ApiException>()),
      reason: 'a payment reference is required',
    );

    voucher = await act(id, 'pay', {
      'reference': 'PC-REL-9931',
      'method': 'Cash — office float',
    });
    expect(voucher['status'], 'paid');
    expect(voucher['status_label'], 'Paid & completed');
    expect(voucher['payment_reference'], 'PC-REL-9931');
    expect(voucher['paid_by'], 'Mwajuma Hamisi');
    expect(
      voucher['amount_in_words'],
      'Four hundred twelve thousand five hundred shillings only',
    );

    // The timeline records every step, ending in Completed.
    final timeline = voucher['timeline'] as List;
    expect(timeline.length, 5);
    expect(
      timeline.map((r) => r['act']),
      containsAll(<String>[
        'Created & submitted',
        'Reviewed & signed',
        'Approved',
        'Paid',
      ]),
    );
    expect(timeline.last['name'], 'Completed');
    expect(timeline.last['state'], 'done');
  });

  test('an employee sees only their own vouchers', () async {
    await signIn('frank@watercom.test');
    final mine =
        (await api.handle(
              'GET',
              '/vouchers',
              query: {'per_page': '200'},
            ))['data']
            as List;
    expect(mine, isNotEmpty);
    expect(
      mine.every((v) => v['requester']['name'] == 'Frank Kessy'),
      isTrue,
      reason: 'an employee register must contain nothing but their own work',
    );

    // Another employee's voucher is not reachable by id either.
    await signIn('baraka@watercom.test');
    final theirs =
        (await api.handle(
              'GET',
              '/vouchers',
              query: {'per_page': '200'},
            ))['data']
            as List;
    final barakaIds = theirs.map((v) => v['id']).toSet();
    final johnId = mine.first['id'] as int;
    expect(barakaIds.contains(johnId), isFalse);
    await expectLater(show(johnId), throwsA(isA<ApiException>()));
  });

  test('a dashboard holds only what is on that person right now', () async {
    // The employee's queue is their own unfinished work, never their history.
    await signIn('frank@watercom.test');
    final employee = await api.handle('GET', '/dashboard') as Map<String, dynamic>;
    final employeeQueue = employee['queue'] as List;
    expect(employeeQueue, isNotEmpty);
    expect(
      employeeQueue.every((v) =>
          v['status'] == 'draft' || v['status'] == 'changes_requested'),
      isTrue,
      reason: 'a dashboard is what is on you, not what you have already sent',
    );

    // The head's queue is only what has actually reached their step.
    await signIn('joseph@watercom.test');
    final hod = await api.handle('GET', '/dashboard') as Map<String, dynamic>;
    for (final v in hod['queue'] as List) {
      final actions = v['actions'] as Map;
      expect(
        actions['sign'] == true ||
            actions['submit_signed'] == true ||
            actions['submit'] == true,
        isTrue,
        reason: 'nothing should sit in a queue its owner cannot act on',
      );
      expect(actions['approve'], isFalse,
          reason: 'the HOD step signs only, wherever it appears');
    }

    // Acting on it takes it out of the queue.
    final target = (hod['queue'] as List).first as Map<String, dynamic>;
    final id = target['id'] as int;
    await act(id, 'sign', {'use_saved_signature': true});
    await act(id, 'submit-signed');
    final after = await api.handle('GET', '/dashboard') as Map<String, dynamic>;
    expect(
      (after['queue'] as List).any((v) => v['id'] == id),
      isFalse,
      reason: 'once signed and sent on, it belongs to the next person',
    );

    // And it is now the approver's.
    await signIn('emmanuel@watercom.test');
    final ceo = await api.handle('GET', '/dashboard') as Map<String, dynamic>;
    expect((ceo['queue'] as List).any((v) => v['id'] == id), isTrue);
  });

  test('the cashier queue holds only approved and paid vouchers', () async {
    await signIn('mwajuma@watercom.test');
    final rows =
        (await api.handle(
              'GET',
              '/vouchers',
              query: {'per_page': '200'},
            ))['data']
            as List;
    expect(rows, isNotEmpty);
    expect(
      rows.every((v) => v['status'] == 'approved' || v['status'] == 'paid'),
      isTrue,
      reason: 'nothing mid-approval should reach the payment queue',
    );

    final dashboard =
        await api.handle('GET', '/dashboard') as Map<String, dynamic>;
    expect(dashboard['data']['headline'], contains('to pay'));
  });

  test('rejecting closes the voucher and notifies the requester', () async {
    await signIn('emmanuel@watercom.test');
    final queue =
        (await api.handle('GET', '/vouchers/pending'))['data'] as List;
    expect(queue, isNotEmpty);

    final target = queue.first as Map<String, dynamic>;
    final id = target['id'] as int;
    final requester = target['requester']['name'] as String;
    final requesterEmail = {
      'Frank Kessy': 'frank@watercom.test',
      'Baraka Ndosi': 'baraka@watercom.test',
      'Doreen Massawe': 'doreen@watercom.test',
      'Gloria Mtei': 'gloria@watercom.test',
    }[requester]!;

    await expectLater(
      act(id, 'reject', const {'comment': 'no'}),
      throwsA(isA<ApiException>()),
      reason: 'a reason shorter than three characters is not a reason',
    );

    final rejected = await act(id, 'reject', {
      'comment': 'Outside the approved budget for this period.',
    });
    expect(rejected['status'], 'rejected');
    expect(rejected['is_terminal'], isTrue);

    await signIn(requesterEmail);
    final inbox = (await api.handle('GET', '/notifications'))['data'] as List;
    expect(
      inbox.any((n) => '${n['title']}'.contains('was rejected')),
      isTrue,
      reason: 'the requester must be told, and told why',
    );
  });

  test(
    'requesting changes returns the voucher to the requester as editable',
    () async {
      await signIn('joseph@watercom.test');
      final queue =
          (await api.handle('GET', '/vouchers/pending'))['data'] as List;
      final id = queue.first['id'] as int;

      await act(id, 'request-changes', {
        'comment': 'Attach the supplier quotation before resubmitting.',
      });

      await signIn('frank@watercom.test');
      final voucher = await show(id);
      expect(voucher['status'], 'changes_requested');
      expect((voucher['actions'] as Map)['edit'], isTrue);
      expect(
        (voucher['actions'] as Map)['submit'],
        isTrue,
        reason: 'the requester can fix it and send it back in',
      );
    },
  );
}

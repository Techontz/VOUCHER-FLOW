/// The demo dataset behind the Phase 1 prototype.
///
/// Neutral company and people names throughout. The shapes mirror the Laravel
/// API resources exactly, so swapping [MockApi] for HTTP changes nothing above
/// this layer.
library;

String iso(int daysAgo, [int hour = 9, int minute = 0]) => DateTime.now()
    .subtract(Duration(days: daysAgo))
    .copyWith(
      hour: hour,
      minute: minute,
      second: 0,
      millisecond: 0,
      microsecond: 0,
    )
    .toIso8601String();

/// A drawn signature, inlined as a PNG so the prototype needs neither a
/// network nor an asset bundle, and so `Image.memory` can render it.
const sampleSignature =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAPAAAABGCAYAAADyxhn6AAADZklEQVR42u3dPUiVYRjGcQ2lIunDoaQIxEXCQTCIoJZApFpa+hobnBpcAh0cQyiXlohAosEIguYoaGhxLKhAECRwj5CgQBDqPvBMqUfNc97P3x+uTX3f57rv6/nQ8752dAAAAAAAAAAAAAAAAAAAUHoO9fb/aaLnHAKKF9rubYK7mRgHFHzF3YlecREoSHj3Eva8JhmVhPD29ne1KlQtuLe7/7kbOKuyqF1427g6Tma4lbciQ3hzPEs3U0+T6/Zt8T3HVRvCm1OQW3TtT6oO4c0mzGNtuuZ31UelAly3ySp0TwegKg39tCZj/uUXW7B1NnbA1lmIgb017xk+CDE0rZ0IoGEz9+MGT3btWR+/8l99P3PErsQiUB7TDzJ+xyFmiMnOrFkyf07zSHiLavwXxmtQ3lh9eSW8fGF+of16wK/Ne0f/WFHK2LgPBVf/FKEQdzhi4msy3rUmj3S+1hHZF+SY2bN+R4+41/deQ2QFQYk8bMfrilQ/34KuKkZLfDxVZB9bHNrLKm7lsJXO5p4WmwTxnappOBR0QrTl1WzYvacf8/Y1rttZ6eBq2g2z8xHRa5u33/Jedatm7n6viLGlquLupjbb5bo3sPBWr8c2Ce8qg6s/7seiVv4eq+2CVLeB2zrn7vklNS3wuSG+91lRP8US17ogvLn017l2+W5CbhLinRgSXzPawk+3dGY4xkHRKu/Op3H0Ed4dhjgHXbXNEuIsdoyCvFE/W3itw8IrxMLb5iDnvY0X3ur/zmWL3rjIzQqdx//5GVeEt/w19lnmau4A1myz6ntU41y5inzAw9aCrI41nLE5Vrr6PlJDQVZ0AAAAAMBuzpi9XABKmJmMP/O8HHoRmgpdCw2Fjrb7oQZUMkCdqXeGUi9Npd5azrKn6xbgIut3eh3p29Bc6H5oInQzPYE1HBoInQj1hLqq8I+uG2NIY+lJYxtIYx1NY59IXswlbxaTV3qmKH8BiRsZCd0OzYY+bPN/YIjqqLWUjdmUlZG6b4H2Nc4Raba/HpoOvQwtaRbaQkupR6ZTzwynHtrnUIFmk01341HH0MnGiwFC50NjoVuh8dBkaCb0JDQfehNaCH0NrYR+hNYzbPT1dM2VdA8L6Z7m0z3OpHseT2MYS2MaTGNsjLVb5QEAAAAAAAAAKDt/AcPmz43fXEUmAAAAAElFTkSuQmCC';

class MockStep {
  MockStep({
    required this.position,
    required this.name,
    required this.nameSw,
    required this.role,
    required this.assigneeHint,
    this.assignedUserId,
    this.canSign = false,
    this.canApprove = false,
    this.canReject = false,
    this.canRequestChanges = false,
    this.canPay = false,
    this.canPrint = true,
    this.minAmount,
    this.maxAmount,
  });

  int position;
  String name, nameSw, role, assigneeHint;
  int? assignedUserId;
  bool canSign, canApprove, canReject, canRequestChanges, canPay, canPrint;
  double? minAmount, maxAmount;

  Map<String, dynamic> get capabilities => {
    'sign': canSign,
    'approve': canApprove,
    'reject': canReject,
    'request_changes': canRequestChanges,
    'pay': canPay,
    'print': canPrint,
    'download': canPrint,
  };
}

/// The default route: raise → HOD signs → CEO approves → cashier pays.
List<MockStep> defaultSteps() => [
  MockStep(
    position: 1,
    name: 'Request',
    nameSw: 'Ombi',
    role: 'employee',
    assigneeHint: 'Voucher creator',
  ),
  MockStep(
    position: 2,
    name: 'Department review',
    nameSw: 'Ukaguzi wa idara',
    role: 'hod',
    assigneeHint: 'Head of the requesting department',
    canSign: true,
    canRequestChanges: true,
  ),
  MockStep(
    position: 3,
    name: 'Executive approval',
    nameSw: 'Idhini ya mkurugenzi',
    role: 'ceo',
    assigneeHint: 'Chief executive / approving manager',
    canApprove: true,
    canReject: true,
    canRequestChanges: true,
  ),
  MockStep(
    position: 4,
    name: 'Payment',
    nameSw: 'Malipo',
    role: 'cashier',
    assigneeHint: 'Cashier / finance officer',
    canPay: true,
  ),
];

class MockUser {
  MockUser({
    required this.id,
    required this.companyId,
    required this.name,
    required this.email,
    required this.role,
    required this.jobTitle,
    required this.employeeCode,
    required this.departmentId,
    this.signature,
    this.locale = 'en',
    this.theme = 'dark',
    this.status = 'active',
  });

  final int id;
  final int? companyId, departmentId;
  final String name, email, employeeCode;
  String role, jobTitle, locale, theme, status;
  String? signature;
}

class MockDepartment {
  const MockDepartment(
    this.id,
    this.companyId,
    this.name,
    this.costCentre,
    this.hodUserId,
    this.managerUserId,
  );
  final int id, companyId;
  final String name, costCentre;
  final int? hodUserId, managerUserId;
}

class MockVoucherType {
  MockVoucherType(
    this.id,
    this.companyId,
    this.name,
    this.nameSw,
    this.prefix,
    this.nextNumber,
  );
  final int id, companyId;
  final String name, nameSw, prefix;
  int nextNumber;
}

class MockApproval {
  MockApproval({
    required this.id,
    required this.voucherId,
    required this.stepPosition,
    required this.actorId,
    required this.actorName,
    required this.action,
    required this.actedAt,
    this.comment,
    this.signature,
  });

  final int id, voucherId, actorId;
  final int? stepPosition;
  final String actorName, action, actedAt;
  final String? comment, signature;
}

class MockComment {
  MockComment(this.id, this.userId, this.body, this.createdAt);
  final int id, userId;
  final String body, createdAt;
}

class MockVoucher {
  MockVoucher({
    required this.id,
    required this.companyId,
    required this.number,
    required this.kind,
    required this.voucherTypeId,
    required this.departmentId,
    required this.requesterId,
    required this.payee,
    required this.purpose,
    required this.description,
    required this.amount,
    required this.paymentMethod,
    required this.category,
    required this.accountRef,
    required this.voucherDate,
    required this.status,
    required this.currentStepPosition,
    required this.createdAt,
    this.currency = 'TZS',
    this.stepSignedAt,
    this.submittedAt,
    this.approvedAt,
    this.rejectedAt,
    this.paidAt,
    this.paymentReference,
    this.paidBy,
    this.notesToApprover,
    List<MockComment>? comments,
    List<String>? attachments,
  }) : comments = comments ?? [],
       attachments = attachments ?? [],
       verificationCode =
           'VF-${(id * 7919 % 9000 + 1000)}-${(id * 104729 % 9000 + 1000)}';

  final int id, companyId, voucherTypeId, requesterId;
  final String number, currency, createdAt, verificationCode;
  String kind, payee, purpose, status, voucherDate;
  String? description, paymentMethod, category, accountRef, notesToApprover;
  String? stepSignedAt, submittedAt, approvedAt, rejectedAt, paidAt;
  String? paymentReference, paidBy;
  int? departmentId, currentStepPosition;
  double amount;
  final List<MockComment> comments;
  final List<String> attachments;
}

class MockNotification {
  MockNotification({
    required this.id,
    required this.userId,
    required this.icon,
    required this.title,
    required this.titleSw,
    required this.body,
    required this.bodySw,
    required this.createdAt,
    this.voucherId,
    this.readAt,
  });

  final int id, userId;
  final String icon, title, titleSw, createdAt;
  final String? body, bodySw;
  final int? voucherId;
  String? readAt;
}

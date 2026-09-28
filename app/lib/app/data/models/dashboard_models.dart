/// Models the dashboard and inbox read beyond the shared resources.
library;

double? _num(dynamic v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// A company workflow as `/workflows` returns it — only what a list row needs
/// to draw a voucher's route (the web's `deriveProgress`).
class QueueWorkflow {
  QueueWorkflow.fromJson(Map<String, dynamic> json)
    : id = _int(json['id']),
      steps =
          (json['steps'] is List ? json['steps'] as List : const [])
              .whereType<Map>()
              .map(
                (e) => QueueWorkflowStep.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
            ..sort((a, b) => a.position.compareTo(b.position));

  final int id;
  final List<QueueWorkflowStep> steps;
}

class QueueWorkflowStep {
  QueueWorkflowStep.fromJson(Map<String, dynamic> json)
    : position = _int(json['position']),
      name = '${json['name'] ?? ''}',
      nameSw = json['name_sw'] is String ? json['name_sw'] as String : null,
      role = '${json['role'] ?? ''}',
      roleLabel = json['role_label'] is String
          ? json['role_label'] as String
          : null,
      canApprove = json['can_approve'] == true,
      canPay = json['can_pay'] == true,
      minAmount = _num(json['min_amount']),
      maxAmount = _num(json['max_amount']);

  final int position;
  final String name, role;
  final String? nameSw, roleLabel;
  final bool canApprove, canPay;
  final double? minAmount, maxAmount;

  /// WorkflowStep::isRequestStep — the step that raises the voucher.
  bool get isRequest => position == 1 || role == 'employee';

  /// WorkflowStep::isPaymentStep — releasing money, not deciding on it.
  bool get isPayment => canPay && !canApprove;

  /// WorkflowStep::appliesToAmount — thresholds, both ends inclusive.
  bool appliesTo(double amount) =>
      (minAmount == null || amount >= minAmount!) &&
      (maxAmount == null || amount <= maxAmount!);

  /// A short, role-level name: "HOD", "Managing Director", "Finance".
  String label(bool sw) {
    if (sw && nameSw != null && nameSw!.isNotEmpty) return nameSw!;
    return (roleLabel != null && roleLabel!.isNotEmpty) ? roleLabel! : name;
  }
}

enum QueueStepState { done, current, pending, rejected }

class QueueProgressStep {
  const QueueProgressStep(this.label, this.state);
  final String label;
  final QueueStepState state;
}

/// The web's `deriveProgress`: where a voucher is in its approval route,
/// derived from the company's real workflow — which steps exist, which apply
/// to this amount, and where the voucher currently sits.
List<QueueProgressStep> deriveQueueProgress({
  required String status,
  required double amount,
  required int? workflowId,
  required int? currentStepPosition,
  required List<QueueWorkflow>? workflows,
  required bool sw,
}) {
  final workflow = workflows?.where((w) => w.id == workflowId).firstOrNull;
  if (workflow == null || workflow.steps.isEmpty) return const [];

  final steps = workflow.steps
      .where((s) => s.isRequest || s.appliesTo(amount))
      .toList();
  final approvals = steps.where((s) => !s.isRequest && !s.isPayment).toList();
  final payment = steps.where((s) => s.isPayment).firstOrNull;
  final at = currentStepPosition;

  final out = <QueueProgressStep>[
    QueueProgressStep(
      sw ? 'Imeandaliwa' : 'Prepared',
      status == 'draft' ? QueueStepState.current : QueueStepState.done,
    ),
  ];

  final states = <QueueStepState>[];
  for (final step in approvals) {
    var state = QueueStepState.pending;
    if (status == 'approved' || status == 'paid') {
      state = QueueStepState.done;
    } else if ((status == 'in_review' || status == 'rejected') && at != null) {
      state = step.position < at
          ? QueueStepState.done
          : step.position == at
          ? (status == 'rejected'
                ? QueueStepState.rejected
                : QueueStepState.current)
          : QueueStepState.pending;
    }
    states.add(state);
  }

  // A rejection with no recorded position still has to show where it ended.
  if (status == 'rejected' &&
      states.isNotEmpty &&
      !states.contains(QueueStepState.rejected)) {
    final i = states.lastIndexWhere((s) => s != QueueStepState.done);
    states[i == -1 ? states.length - 1 : i] = QueueStepState.rejected;
  }

  for (var i = 0; i < approvals.length; i++) {
    out.add(QueueProgressStep(approvals[i].label(sw), states[i]));
  }

  if (payment != null) {
    out.add(
      QueueProgressStep(
        payment.label(sw),
        status == 'paid'
            ? QueueStepState.done
            : status == 'approved'
            ? QueueStepState.current
            : QueueStepState.pending,
      ),
    );
  }
  return out;
}

/// One page of the inbox, with the unread count the API sends alongside it.
class NotificationPage<T> {
  const NotificationPage(this.items, this.unreadCount);
  final List<T> items;
  final int unreadCount;
}

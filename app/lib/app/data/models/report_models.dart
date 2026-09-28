/// The reports screen's data: GET /reports (the catalogue and the caller's
/// reach) and GET /reports/{kind} (one report) — ReportController.
library;

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
int? _intOrNull(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
String? _str(dynamic v) => v == null ? null : '$v';

/// One report this role may run.
class ReportKind {
  ReportKind.fromJson(Map<String, dynamic> j)
    : key = '${j['key']}',
      icon = '${j['icon'] ?? ''}',
      titleEn = '${j['title'] ?? j['key']}',
      titleSw = '${j['title_sw'] ?? j['title'] ?? j['key']}',
      bodyEn = '${j['body'] ?? ''}',
      bodySw = '${j['body_sw'] ?? j['body'] ?? ''}';

  final String key, icon, titleEn, titleSw, bodyEn, bodySw;

  String title(bool sw) => sw ? titleSw : titleEn;
  String body(bool sw) => sw ? bodySw : bodyEn;
}

/// How far this caller's reporting reaches (ReportController::scopeDescriptor).
/// A department picker may narrow it and can never widen it.
class ReportScope {
  ReportScope.fromJson(Map<String, dynamic> j)
    : level = '${j['level'] ?? 'own'}',
      label = '${j['label'] ?? ''}',
      departmentIds = j['department_ids'] is List
          ? (j['department_ids'] as List).map(_int).toList()
          : null;

  /// own · departments · company
  final String level;
  final String label;

  /// Null for the whole company.
  final List<int>? departmentIds;

  bool get isOwn => level == 'own';
  bool get isCompany => level == 'company' || departmentIds == null;
}

/// The catalogue call's whole answer.
class ReportCatalogue {
  ReportCatalogue(this.kinds, this.scope);

  final List<ReportKind> kinds;
  final ReportScope? scope;
}

/// Figures above the rows. The money reports add the released/outstanding
/// and bank/cash split.
class ReportSummary {
  ReportSummary.fromJson(Map<String, dynamic> j)
    : count = _int(j['count']),
      totalText = '${j['total_text'] ?? '—'}',
      approvedTotalText = '${j['approved_total_text'] ?? '—'}',
      paidTotalText = _str(j['paid_total_text']),
      paidCount = _intOrNull(j['paid_count']),
      bankTotalText = _str(j['bank_total_text']),
      bankCount = _intOrNull(j['bank_count']),
      cashTotalText = _str(j['cash_total_text']),
      cashCount = _intOrNull(j['cash_count']),
      outstandingTotalText = _str(j['outstanding_total_text']),
      outstandingCount = _intOrNull(j['outstanding_count']);

  final int count;
  final String totalText, approvedTotalText;
  final String? paidTotalText, bankTotalText, cashTotalText, outstandingTotalText;
  final int? paidCount, bankCount, cashCount, outstandingCount;
}

/// One report: its column headings, the rows (raw values — the same ones
/// the exports carry) and the summary.
class ReportResult {
  ReportResult.fromJson(Map<String, dynamic> j)
    : kind = '${j['kind']}',
      headings = ((j['headings'] as List?) ?? const []).map((e) => '$e').toList(),
      rows = ((j['rows'] as List?) ?? const [])
          .map((r) => r is List ? List<Object?>.from(r) : <Object?>[r])
          .toList(),
      summary = ReportSummary.fromJson((j['summary'] as Map?)?.cast<String, dynamic>() ?? const {}),
      generatedAt = DateTime.tryParse('${j['generated_at']}');

  final String kind;
  final List<String> headings;
  final List<List<Object?>> rows;
  final ReportSummary summary;
  final DateTime? generatedAt;
}

/// A person to filter by (GET /directory).
class ReportPerson {
  ReportPerson.fromJson(Map<String, dynamic> j)
    : id = _int(j['id']),
      name = '${j['name']}',
      departmentId = _intOrNull(j['department_id']);

  final int id;
  final String name;
  final int? departmentId;
}

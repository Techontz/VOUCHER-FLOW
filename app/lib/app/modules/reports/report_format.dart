import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Screen formatting for report cells. Formatting is for the screen only —
/// the same rows feed the PDF, Excel and CSV exports, which keep their raw
/// values (web reports page).
class ReportFormat {
  const ReportFormat._();

  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}(T|$)');
  static final _ref = RegExp(r'^[A-Z]{2,5}-\d{4}-\d+$');
  static final _numeric = RegExp(
    r'amount|value|total|turnaround|vouchers|approved|rejected|pending|requests|paid so far|balance',
    caseSensitive: false,
  );

  static const _swMonths = [
    'Jan',
    'Feb',
    'Mac',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  static bool isDate(Object? cell) => cell is String && _date.hasMatch(cell);
  static bool isRef(Object? cell) => cell is String && _ref.hasMatch(cell);

  /// A column the web right-aligns as a figure.
  static bool isNumericHeading(String heading) => _numeric.hasMatch(heading);

  /// 24 Sep 2026 (Swahili month names under sw) — the web's formatDate.
  static String date(DateTime? d, {bool sw = false}) {
    if (d == null) return '—';
    if (sw) return '${d.day} ${_swMonths[d.month - 1]} ${d.year}';
    return DateFormat('d MMM yyyy', 'en_US').format(d);
  }

  /// A number as the web shows it: grouped, at most two decimals.
  static String number(num n) => NumberFormat('#,##0.##', 'en_US').format(n);

  static String cell(Object? value, {bool sw = false}) {
    if (value == null) return '—';
    if (value is num) return number(value);
    if (isDate(value)) return date(DateTime.tryParse(value as String), sw: sw);
    final text = '$value';
    return text.isEmpty ? '—' : text;
  }

  /// The badge tone for a server status or outcome word — the web's
  /// statusTone: money released or due is green, part paid or returned is
  /// amber, a refusal red, draft and cancelled neutral, the rest in progress.
  static String statusTag(String text) {
    final s = text.toLowerCase();
    bool has(List<String> words) => words.any(s.contains);
    if (has([
      'partially',
      'changes',
      'returned',
      'sehemu',
      'mabadiliko',
      'imerudishwa',
    ])) {
      return 'tag-warn';
    }
    if (has(['reject', 'imekataliwa'])) return 'tag-accent-2';
    if (has(['paid', 'awaiting payment', 'imelipwa', 'inasubiri malipo']) ||
        s == 'approved' ||
        s == 'imeidhinishwa') {
      return 'tag-accent';
    }
    if (has(['draft', 'cancel', 'rasimu', 'imefutwa']) || s == '—') {
      return 'tag-neutral';
    }
    return 'tag-info';
  }

  /// The catalogue's `ph-*` icon names.
  static IconData icon(String name) => switch (name) {
    'ph-receipt' => PhosphorIconsRegular.receipt,
    'ph-coins' => PhosphorIconsRegular.coins,
    'ph-wallet' => PhosphorIconsRegular.wallet,
    'ph-money' => PhosphorIconsRegular.money,
    'ph-buildings' => PhosphorIconsRegular.buildings,
    'ph-user' => PhosphorIconsRegular.user,
    'ph-list-checks' => PhosphorIconsRegular.listChecks,
    'ph-calendar' => PhosphorIconsRegular.calendar,
    _ => PhosphorIconsRegular.chartLine,
  };
}

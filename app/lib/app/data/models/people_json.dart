/*
 * JSON readers shared by the Fleet and HR models. Laravel sends decimals as
 * strings ("180.000") and dates as ISO strings; these turn them into numbers
 * and days once, so screens never parse.
 */

double jd(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

double? jdn(dynamic v) => v == null || '$v'.isEmpty ? null : jd(v);

int ji(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

int? jin(dynamic v) => v == null ? null : ji(v);

String? js(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

String jstr(dynamic v) => v == null ? '' : '$v';

bool jb(dynamic v) => v == true || v == 1 || v == '1';

/// A calendar day ("2026-11-12" or "2026-11-12T00:00:00.000000Z"); only the
/// day is read, so midnight UTC never becomes yesterday west of Greenwich.
DateTime? jday(dynamic v) {
  final s = js(v);
  if (s == null || s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

/// A moment in time, shown in the phone's zone.
DateTime? jtime(dynamic v) {
  final s = js(v);
  return s == null ? null : DateTime.tryParse(s)?.toLocal();
}

Map<String, dynamic>? jmap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;

List<T> jlist<T>(dynamic v, T Function(Map<String, dynamic>) read) =>
    (v is List ? v : const []).whereType<Map>().map((e) => read(Map<String, dynamic>.from(e))).toList();

/// "2026-11-12", as the API takes a date.
String jdate(DateTime d) => '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';

/// Days from today to [d] (negative once it has passed).
int daysUntil(DateTime d) {
  final now = DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
}

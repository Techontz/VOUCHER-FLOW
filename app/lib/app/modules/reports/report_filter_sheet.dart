import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../widgets/vf/vf.dart';
import 'report_format.dart';
import 'reports_controller.dart';

/// A filter value in words, for the active-filter chips.
String reportFilterValueLabel(
  ReportsController c,
  String key,
  String value, {
  required bool sw,
}) {
  String date(String v) => ReportFormat.date(DateTime.tryParse(v), sw: sw);
  final id = int.tryParse(value);
  return switch (key) {
    'from' => '${'reports.from'.tr} ${date(value)}',
    'to' => '${'reports.to'.tr} ${date(value)}',
    'department_id' =>
      c.departments.firstWhereOrNull((d) => d.id == id)?.name ?? value,
    'requester_id' =>
      c.people.firstWhereOrNull((p) => p.id == id)?.name ?? value,
    'voucher_type_id' =>
      c.types.firstWhereOrNull((x) => x.id == id)?.label ?? value,
    'kind' =>
      value == 'cash' ? 'reports.cashVoucher'.tr : 'reports.bankVoucher'.tr,
    'status' =>
      c.statusOptions.firstWhereOrNull((o) => o.value == value)?.labelKey.tr ??
          value,
    _ => value,
  };
}

/// The report's filters in a bottom sheet (the web's filter toolbar, which a
/// phone has no room for). Returns the chosen filters, or null if dismissed.
Future<Map<String, String>?> showReportFilterSheet(
  BuildContext context,
  ReportsController c,
) {
  final draft = Map<String, String>.of(c.filters);
  final sw = Get.locale?.languageCode == 'sw';

  return showVouchFlowBottomSheet<Map<String, String>>(
    context,
    title: 'reports.filters'.tr,
    child: StatefulBuilder(
      builder: (context, setState) {
        void set(String key, String? v) => setState(() => draft[key] = v ?? '');
        final scope = c.scope.value;
        final payment = c.config.status == 'payment';
        final statusValues = c.statusOptions.map((o) => o.value).toList();

        final fields = <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _DateField(
                  label: 'reports.from'.tr,
                  value: draft['from']!,
                  sw: sw,
                  onChanged: (v) => set('from', v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateField(
                  label: 'reports.to'.tr,
                  value: draft['to']!,
                  sw: sw,
                  onChanged: (v) => set('to', v),
                ),
              ),
            ],
          ),
          if (c.shows('department_id'))
            VouchFlowDropdown<String>(
              label: 'reports.department'.tr,
              items: ['', ...c.pickableDepartments.map((d) => '${d.id}')],
              value: draft['department_id'],
              itemLabel: (v) => v.isEmpty
                  ? (scope?.level == 'departments'
                        ? scope!.label
                        : 'reports.allDepartments'.tr)
                  : c.pickableDepartments
                            .firstWhereOrNull((d) => '${d.id}' == v)
                            ?.name ??
                        v,
              onChanged: (v) => set('department_id', v),
            ),
          if (c.shows('requester_id'))
            VouchFlowDropdown<String>(
              label: 'reports.employee'.tr,
              items: ['', ...c.pickablePeople.map((p) => '${p.id}')],
              value: draft['requester_id'],
              itemLabel: (v) => v.isEmpty
                  ? 'reports.allEmployees'.tr
                  : c.pickablePeople
                            .firstWhereOrNull((p) => '${p.id}' == v)
                            ?.name ??
                        v,
              onChanged: (v) => set('requester_id', v),
            ),
          if (c.shows('kind'))
            VouchFlowDropdown<String>(
              label: 'reports.format'.tr,
              items: const ['', 'bank', 'cash'],
              value: draft['kind'],
              itemLabel: (v) => switch (v) {
                'bank' => 'reports.bankVoucher'.tr,
                'cash' => 'reports.cashVoucher'.tr,
                _ => 'reports.all'.tr,
              },
              onChanged: (v) => set('kind', v),
            ),
          if (c.shows('voucher_type_id'))
            VouchFlowDropdown<String>(
              label: 'reports.type'.tr,
              items: ['', ...c.types.map((x) => '${x.id}')],
              value: draft['voucher_type_id'],
              itemLabel: (v) => v.isEmpty
                  ? 'reports.allTypes'.tr
                  : c.types.firstWhereOrNull((x) => '${x.id}' == v)?.label ?? v,
              onChanged: (v) => set('voucher_type_id', v),
            ),
          if (c.shows('status'))
            VouchFlowDropdown<String>(
              label: payment ? 'reports.paymentStatus'.tr : 'reports.status'.tr,
              items: ['', ...statusValues],
              value: statusValues.contains(draft['status'])
                  ? draft['status']
                  : '',
              itemLabel: (v) => v.isEmpty
                  ? (payment
                        ? 'reports.allPaymentStatuses'.tr
                        : 'reports.allStatuses'.tr)
                  : c.statusOptions.firstWhere((o) => o.value == v).labelKey.tr,
              onChanged: (v) => set('status', v),
            ),
        ];

        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                fields[i],
              ],
            ],
          ),
        );
      },
    ),
    actions: [
      Builder(
        builder: (ctx) => VouchFlowButton(
          label: 'reports.clear'.tr,
          variant: VfButtonVariant.secondary,
          onPressed: () {
            // Clearing keeps the search box: it lives outside the sheet.
            final cleared = blankReportFilters()..['q'] = c.filters['q'] ?? '';
            Navigator.of(ctx).pop(cleared);
          },
        ),
      ),
      Builder(
        builder: (ctx) => VouchFlowButton(
          label: 'reports.apply'.tr,
          onPressed: () => Navigator.of(
            ctx,
          ).pop(Map<String, String>.of(draft)..['q'] = c.filters['q'] ?? ''),
        ),
      ),
    ],
  );
}

/// A date filter in the web's input style: tap for a calendar, × to clear.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.sw,
    required this.onChanged,
  });

  final String label;
  final String value;
  final bool sw;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final date = DateTime.tryParse(value);

    Future<void> pick() async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: date ?? now,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 5, 12, 31),
      );
      if (picked != null) onChanged(DateFormat('yyyy-MM-dd').format(picked));
    }

    return VouchFlowField(
      label: label,
      child: Material(
        color: t.inputBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          side: BorderSide(color: t.inputBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: pick,
          child: SizedBox(
            height: VfSize.inputH,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  PhosphorIconsRegular.calendarBlank,
                  size: 17,
                  color: t.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    date == null
                        ? 'reports.anyDate'.tr
                        : ReportFormat.date(date, sw: sw),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.body.copyWith(
                      color: date == null ? t.placeholder : t.text,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                if (date != null)
                  SizedBox(
                    width: 40,
                    height: 44,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'action.clear'.tr,
                      onPressed: () => onChanged(''),
                      icon: Icon(
                        PhosphorIconsRegular.x,
                        size: 15,
                        color: t.muted,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

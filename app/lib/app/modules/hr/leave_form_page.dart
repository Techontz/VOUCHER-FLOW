import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart' show ErpFmt;
import '../../data/models/hr_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/hr_repository.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../fleet/fleet_widgets.dart' show BottomActionBar;
import 'hr_widgets.dart';

/// Applying for leave in three taps: the kind (each showing what is left),
/// the first and last day, an optional reason. The API counts the days
/// (working days for most kinds) and routes the request to the approver.
/// Opened with an optional {'typeId': int}; closes with `true` once sent.
class LeaveFormPage extends StatefulWidget {
  const LeaveFormPage({super.key, this.typeId});

  final int? typeId;

  @override
  State<LeaveFormPage> createState() => _LeaveFormPageState();
}

class _LeaveFormPageState extends State<LeaveFormPage> {
  final _repo = HrRepository.to;
  final _draft = LeaveDraft();
  List<HrLeaveType>? _types;
  Map<int, HrLeaveBalance> _balances = const {};
  String? _loadError;
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    _draft.typeId = widget.typeId ?? (args is Map ? args['typeId'] as int? : null);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final types = await _repo.leaveTypes();
      final (_, balances) = await _repo.myLeave();
      if (!mounted) return;
      setState(() {
        _types = types;
        _balances = {for (final b in balances) b.typeId: b};
        _draft.typeId ??= types.where((t) => t.code == 'annual').firstOrNull?.id ?? types.firstOrNull?.id;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'state.offline'.tr);
    }
  }

  Future<void> _pick({required bool start}) async {
    final now = DateTime.now();
    final initial = (start ? _draft.start : _draft.end ?? _draft.start) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: start ? DateTime(now.year, now.month - 1) : (_draft.start ?? DateTime(now.year, now.month - 1)),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _draft.start = picked;
        if (_draft.end == null || _draft.end!.isBefore(picked)) _draft.end = picked;
      } else {
        _draft.end = picked;
      }
    });
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (_draft.typeId == null || _draft.start == null || _draft.end == null) {
      setState(() => _error = ApiException(422, 'hr.pickDates'.tr));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final r = await _repo.requestLeave(_draft);
      Get.back(result: true);
      showToast('hr.leaveSent'.tr, body: '${r.type} · ${daysLabel(r.days)}');
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = ApiException(0, 'state.offline'.tr); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = _types;
    return VouchFlowPushedScaffold(
      title: 'hr.applyLeave'.tr,
      body: ErpGate(
        module: 'hr',
        permission: 'hr.self',
        builder: (context) => types == null
            ? (_loadError == null
                  ? const VfLoadingView()
                  : ErpPageBody(children: [VouchFlowErrorState(message: _loadError!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
            : _form(context, types),
      ),
      bottomBar: types == null
          ? null
          : BottomActionBar(
              children: [
                VouchFlowButton(
                  label: 'hr.sendRequest'.tr,
                  icon: PhosphorIconsRegular.paperPlaneTilt,
                  expand: true,
                  height: 54,
                  loading: _busy,
                  onPressed: _busy ? null : _send,
                ),
              ],
            ),
    );
  }

  Widget _form(BuildContext context, List<HrLeaveType> types) {
    final t = context.vf;
    final balance = _balances[_draft.typeId];
    final days = _draft.calendarDays;
    return ErpPageBody(
      children: [
        Text('hr.whichLeave'.tr, style: VfType.cardTitle.copyWith(color: t.text)),
        const SizedBox(height: 10),
        VouchFlowPanel(
          padded: false,
          child: Column(
            children: [
              for (var i = 0; i < types.length; i++)
                VouchFlowListRow(
                  key: ValueKey('leave-type-${types[i].id}'),
                  divider: i > 0,
                  icon: _draft.typeId == types[i].id ? PhosphorIconsFill.checkCircle : PhosphorIconsRegular.circle,
                  iconColor: _draft.typeId == types[i].id ? t.primary : t.faint,
                  title: types[i].name,
                  subtitle: [
                    if (_balances[types[i].id]?.available case final a?) 'hr.daysLeftN'.trParams({'n': ErpFmt.qty(double.parse(a.toStringAsFixed(1)))}),
                    if (!types[i].paid) 'hr.unpaid'.tr,
                  ].join(' · '),
                  onTap: () => setState(() => _draft.typeId = types[i].id),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text('hr.whichDays'.tr, style: VfType.cardTitle.copyWith(color: t.text)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: VouchFlowTextField(
                key: ValueKey('start-${_draft.start}'),
                label: 'hr.firstDay'.tr,
                required: true,
                readOnly: true,
                initialValue: _draft.start == null ? '' : dashDate(_draft.start),
                placeholder: 'hr.pick'.tr,
                suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
                error: _error?.field('start_date'),
                onTap: () => _pick(start: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: VouchFlowTextField(
                key: ValueKey('end-${_draft.end}'),
                label: 'hr.lastDay'.tr,
                required: true,
                readOnly: true,
                initialValue: _draft.end == null ? '' : dashDate(_draft.end),
                placeholder: 'hr.pick'.tr,
                suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
                error: _error?.field('end_date'),
                onTap: () => _pick(start: false),
              ),
            ),
          ],
        ),
        if (days > 0) ...[
          const SizedBox(height: 4),
          VouchFlowAlert(
            tone: balance?.available != null && days > balance!.available! ? VfTone.warn : VfTone.info,
            icon: PhosphorIconsRegular.calendarCheck,
            message: [
              'hr.calendarDays'.trParams({'n': '$days'}),
              if (balance?.available != null) 'hr.youHave'.trParams({'n': ErpFmt.qty(double.parse(balance!.available!.toStringAsFixed(1)))}),
            ].join(' '),
          ),
        ],
        const SizedBox(height: 14),
        VouchFlowTextField(
          label: 'hr.reason'.tr,
          hint: 'hr.optional'.tr,
          maxLines: 3,
          maxLength: 500,
          error: _error?.field('reason'),
          onChanged: (v) => _draft.reason = v,
        ),
        if (_error != null && _error!.errors.isEmpty) ...[
          erpGap,
          VouchFlowAlert(message: _error!.message, tone: VfTone.bad, icon: PhosphorIconsRegular.warningCircle),
        ],
      ],
    );
  }
}

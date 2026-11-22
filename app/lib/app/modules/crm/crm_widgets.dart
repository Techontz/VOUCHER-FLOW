import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/crm_repository.dart';
import '../../data/services/erp_service.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/ops_kit.dart';

/*
 * Pieces the CRM screens share: how stages, lead statuses, sources and
 * activity types read and look, a deal and an activity as list rows, and
 * the move-stage sheet the pipeline and a deal both open.
 */

String crmStageLabel(String s) => 'crm.stage.$s'.tr;
String crmLeadStatusLabel(String s) => 'crm.lead.$s'.tr;
String crmSourceLabel(String s) => 'crm.src.$s'.tr;
String crmActivityLabel(String s) => 'crm.act.$s'.tr;
String crmReasonLabel(String s) => 'crm.reason.$s'.tr;

VfTone crmStageTone(String s) => switch (s) {
  CrmStage.proposal => VfTone.info,
  CrmStage.negotiation => VfTone.warn,
  CrmStage.won => VfTone.ok,
  CrmStage.lost => VfTone.bad,
  _ => VfTone.neutral,
};

VfTone crmLeadTone(String s) => switch (s) {
  'new' => VfTone.info,
  'contacted' => VfTone.warn,
  'qualified' || 'converted' => VfTone.ok,
  'lost' => VfTone.bad,
  _ => VfTone.neutral,
};

IconData crmActivityIcon(String type) => switch (type) {
  'call' => PhosphorIconsRegular.phone,
  'meeting' => PhosphorIconsRegular.usersThree,
  'visit' => PhosphorIconsRegular.mapPin,
  _ => PhosphorIconsRegular.checkSquare,
};

/// "TZS 42M" for a card, the full figure elsewhere.
String crmMoney(num v, {bool compact = true}) {
  final c = ErpService.to.currency;
  return compact ? ErpFmt.compactMoney(v, c) : '$c ${ErpFmt.amount(v)}';
}

/// A deal as a list row: title, customer and close date, value, stage.
class CrmDealRow extends StatelessWidget {
  const CrmDealRow({super.key, required this.deal, required this.onTap, this.divider = true, this.onMove, this.showStage = true});

  final CrmOpportunity deal;
  final VoidCallback onTap;
  final VoidCallback? onMove;
  final bool divider, showStage;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final d = deal;
    final tone = crmStageTone(d.stage).colors(t).$1;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.handshake,
      iconColor: tone,
      title: d.title,
      titleMaxLines: 2,
      subtitle: [
        ?d.customer,
        if (d.expectedClose != null) dashDate(d.expectedClose),
        '${d.probability}%',
        if (d.owner != null && ErpService.to.can('crm.view_all')) d.owner!,
      ].join(' · '),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                crmMoney(d.value),
                style: VfType.bodyStrong.copyWith(color: t.text, fontSize: 14, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              if (showStage) ...[const SizedBox(height: 3), OpsBadge(crmStageLabel(d.stage), tone: crmStageTone(d.stage))],
            ],
          ),
          if (onMove != null)
            IconButton(
              tooltip: 'crm.moveTo'.tr,
              onPressed: onMove,
              icon: Icon(PhosphorIconsRegular.arrowsDownUp, size: 19, color: t.primaryText),
            ),
        ],
      ),
    );
  }
}

/// An activity as a list row; a round check marks it done when [onDone] is set.
class CrmActivityRow extends StatelessWidget {
  const CrmActivityRow({super.key, required this.activity, this.divider = true, this.onTap, this.onDone, this.showLink = true});

  final CrmActivity activity;
  final bool divider, showLink;
  final VoidCallback? onTap, onDone;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final a = activity;
    final overdue = a.overdue(DateTime.now());
    final color = a.isDone ? t.successStrong : overdue ? t.dangerStrong : t.primary;
    return VouchFlowListRow(
      divider: divider,
      icon: crmActivityIcon(a.type),
      iconColor: color,
      title: a.subject,
      titleMaxLines: 2,
      onTap: onTap,
      subtitle: [
        crmActivityLabel(a.type),
        if (a.isDone) '${'crm.done'.tr} ${dashDate(a.completedAt)}' else if (a.dueAt != null) dashDateTime(a.dueAt),
        if (showLink) ?a.linkedTo,
        if (a.isDone && a.outcome != null) a.outcome!,
      ].join(' · '),
      trailing: a.isDone
          ? Icon(PhosphorIconsFill.checkCircle, size: 22, color: t.successStrong)
          : onDone != null
          ? IconButton(
              tooltip: 'crm.markDone'.tr,
              onPressed: onDone,
              icon: Icon(PhosphorIconsRegular.circle, size: 24, color: overdue ? t.dangerStrong : t.muted),
            )
          : overdue
          ? OpsBadge('crm.overdue'.tr, tone: VfTone.bad)
          : null,
    );
  }
}

/// Marks [a] done, asking for its outcome; true once it is.
Future<bool> crmComplete(BuildContext context, CrmActivity a) async {
  final done = await showVouchFlowDialog<String>(
    context,
    dialog: VouchFlowDialog(
      icon: crmActivityIcon(a.type),
      tone: VfTone.ok,
      title: 'crm.completeQ'.trParams({'subject': a.subject}),
      child: OpsConfirm(
        confirmLabel: 'crm.markDone'.tr,
        icon: PhosphorIconsRegular.checkCircle,
        fieldLabel: 'crm.outcome'.tr,
        fieldHint: 'crm.outcomeHint'.tr,
        run: (outcome) async {
          await CrmRepository.to.complete(a.id, outcome);
          return 'ok';
        },
      ),
    ),
  );
  if (done == null) return false;
  showToast('crm.markedDone'.tr, body: a.subject);
  return true;
}

/// Moves [deal] to another stage: open stages at once, Won or Lost with a
/// reason (required for Lost) and a note. True once moved.
Future<bool> crmMoveStage(BuildContext context, CrmOpportunity deal) async {
  final moved = await showVfSheet<String>(context, builder: (_) => _MoveSheet(deal: deal));
  if (moved == null) return false;
  showToast('crm.moved'.trParams({'number': deal.number, 'stage': crmStageLabel(moved)}));
  return true;
}

class _MoveSheet extends StatefulWidget {
  const _MoveSheet({required this.deal});

  final CrmOpportunity deal;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  late String _stage = widget.deal.stage;
  String? _reason;

  bool get _closing => _stage == CrmStage.won || _stage == CrmStage.lost;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final d = widget.deal;
    final reasons = _stage == CrmStage.won ? CrmStage.winReasons : CrmStage.lossReasons;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('crm.moveTo'.tr, style: VfType.sectionTitle.copyWith(color: t.text)),
                const SizedBox(height: 4),
                Text('${d.number} · ${d.title}', style: VfType.small.copyWith(color: t.text2)),
                const SizedBox(height: 14),
                Container(
                  decoration: vfCardDecoration(t),
                  child: Column(
                    children: [
                      for (var i = 0; i < CrmStage.all.length; i++)
                        _StageOption(
                          stage: CrmStage.all[i],
                          divider: i > 0,
                          current: d.stage == CrmStage.all[i],
                          selected: _stage == CrmStage.all[i],
                          onTap: () => setState(() {
                            _stage = CrmStage.all[i];
                            _reason = null;
                          }),
                        ),
                    ],
                  ),
                ),
                if (_closing) ...[
                  const SizedBox(height: 16),
                  Text(
                    _stage == CrmStage.won ? 'crm.whyWon'.tr : 'crm.whyLost'.tr,
                    style: VfType.label.copyWith(color: t.text),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in reasons)
                        VouchFlowFilterChip(label: crmReasonLabel(r), selected: _reason == r, onTap: () => setState(() => _reason = r)),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                OpsConfirm(
                  key: ValueKey(_stage),
                  confirmLabel: _stage == CrmStage.won
                      ? 'crm.closeWon'.tr
                      : _stage == CrmStage.lost
                      ? 'crm.closeLost'.tr
                      : 'crm.move'.tr,
                  danger: _stage == CrmStage.lost,
                  fieldLabel: _closing ? 'crm.note'.tr : null,
                  ready: _stage != d.stage && (_stage != CrmStage.lost || _reason != null),
                  run: (note) async {
                    await CrmRepository.to.moveStage(d.id, _stage, reason: _closing ? _reason : null, note: note);
                    return _stage;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StageOption extends StatelessWidget {
  const _StageOption({required this.stage, required this.divider, required this.current, required this.selected, required this.onTap});

  final String stage;
  final bool divider, current, selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final tone = crmStageTone(stage).colors(t).$1;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
          decoration: BoxDecoration(
            border: divider ? Border(top: BorderSide(color: t.isDark ? t.glassBorder : t.border)) : null,
          ),
          child: Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  crmStageLabel(stage),
                  style: VfType.label.copyWith(color: t.text, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                ),
              ),
              if (current) Text('crm.current'.tr, style: VfType.meta.copyWith(color: t.muted)),
              const SizedBox(width: 8),
              Icon(
                selected ? PhosphorIconsFill.radioButton : PhosphorIconsRegular.circle,
                size: 22,
                color: selected ? t.primary : t.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "1 deal", "4 deals".
String crmDeals(int n) => n == 1 ? 'crm.oneDeal'.tr : 'crm.dealsN'.trParams({'n': '$n'});

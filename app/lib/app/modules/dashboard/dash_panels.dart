import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../widgets/vf/vf.dart';
import 'dash_bits.dart';

/// Where a row's hairline starts: past a 40px lead tile and its gap.
const _rowInset = 68.0;

TextStyle _title(VfTokens t) =>
    VfType.bodyStrong.copyWith(color: t.text, fontSize: 14.5, height: 1.35);

TextStyle _meta(VfTokens t) =>
    VfType.meta.copyWith(color: t.muted, fontSize: 12.5);

TextStyle _amount(VfTokens t) => VfType.small.copyWith(
  color: t.text,
  fontWeight: FontWeight.w700,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// A list row: lead tile, title, one muted line, and what sits on the right.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.lead,
    required this.title,
    this.meta,
    this.trailing,
    this.onTap,
    this.last = false,
  });

  final Widget lead;
  final Widget title;
  final String? meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return DashRow(
      last: last,
      inset: _rowInset,
      onTap: onTap,
      child: Row(
        children: [
          lead,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                title,
                if (meta != null && meta!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _meta(t),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: trailing,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Who did what to which voucher, newest first.
class ActivityPanel extends StatelessWidget {
  const ActivityPanel({
    super.key,
    required this.title,
    required this.rows,
    required this.selfId,
    required this.onOpen,
    required this.link,
  });

  final String title;
  final List<DashboardActivity> rows;
  final int? selfId;
  final void Function(int voucherId) onOpen;
  final (String, VoidCallback) link;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return DashPanel(
      title: title,
      trailing: DashLink(label: link.$1, onTap: link.$2),
      child: rows.isEmpty
          ? DashEmpty('dash.activity.empty'.tr)
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  _activityRow(t, rows[i], i == rows.length - 1),
              ],
            ),
    );
  }

  Widget _activityRow(VfTokens t, DashboardActivity row, bool last) {
    final you = row.actorId != null && row.actorId == selfId;
    final (IconData icon, Color colour) = switch (row.action) {
      'approved' => (PhosphorIconsRegular.sealCheck, t.successStrong),
      'paid' => (PhosphorIconsRegular.money, t.successStrong),
      'signed' => (PhosphorIconsRegular.signature, t.primary),
      'submitted' ||
      'resubmitted' => (PhosphorIconsRegular.paperPlaneTilt, t.primary),
      'rejected' => (PhosphorIconsRegular.xCircle, t.dangerStrong),
      'changes_requested' => (
        PhosphorIconsRegular.arrowUUpLeft,
        t.warningStrong,
      ),
      _ => (PhosphorIconsRegular.clockCounterClockwise, t.text2),
    };
    final meta = [
      ?row.amountText,
      dashRelative(DateTime.tryParse(row.at ?? '')?.toLocal()),
    ].join(' · ');

    return _ListRow(
      last: last,
      onTap: () => onOpen(row.voucherId),
      lead: DashIconTile(icon: icon, color: colour),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: you ? 'dash.activity.you'.tr : row.actor,
              style: TextStyle(color: t.text, fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: ' ${dashTr('activity.${row.action}', row.actionLabel)} ',
            ),
            TextSpan(
              text: row.voucherNumber,
              style: TextStyle(
                color: t.primaryText,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: VfType.small.copyWith(color: t.text2, height: 1.35),
      ),
      meta: meta,
      trailing: Icon(PhosphorIconsBold.caretRight, size: 13, color: t.faint),
    );
  }
}

/// The platform's own queue: companies that need a conversation.
class AttentionCompaniesPanel extends StatelessWidget {
  const AttentionCompaniesPanel({
    super.key,
    required this.rows,
    required this.onAll,
    required this.onOpen,
  });

  final List<DashboardAttention> rows;
  final VoidCallback onAll;
  final void Function(int id) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return DashPanel(
      title: 'dashboard.companiesNeedingAttention'.tr,
      count: rows.length,
      trailing: DashLink(label: 'dashboard.all'.tr, onTap: onAll),
      child: rows.isEmpty
          ? DashEmpty(
              dashTr('dash.banner.clear', 'Nothing needs your attention.'),
            )
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  _ListRow(
                    last: i == rows.length - 1,
                    onTap: () => onOpen(rows[i].id),
                    lead: DashIconTile(
                      icon: PhosphorIconsRegular.buildings,
                      color: t.warningStrong,
                    ),
                    title: Text(
                      rows[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _title(t),
                    ),
                    meta: [
                      if (rows[i].note.isNotEmpty) rows[i].note,
                      ?rows[i].plan,
                      '${rows[i].usersCount} ${'dashboard.users'.tr}',
                    ].join(' · '),
                    trailing: VouchFlowStatusBadge(
                      label: rows[i].status,
                      tag: rows[i].status == 'trial'
                          ? 'tag-info'
                          : 'tag-accent-2',
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The platform's latest subscription invoices.
class RecentPaymentsPanel extends StatelessWidget {
  const RecentPaymentsPanel({
    super.key,
    required this.rows,
    required this.onAll,
  });

  final List<DashboardInvoice> rows;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return DashPanel(
      title: 'dashboard.recentPayments'.tr,
      trailing: DashLink(label: 'dashboard.all'.tr, onTap: onAll),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _ListRow(
              last: i == rows.length - 1,
              lead: DashIconTile(
                icon: PhosphorIconsRegular.creditCard,
                color: t.primary,
              ),
              title: Text(
                rows[i].company ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _title(t),
              ),
              meta:
                  '${'dashboard.invoice'.tr} ${rows[i].number} · ${dashDate(rows[i].createdAt)}',
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dashCompactMoney(rows[i].total, rows[i].currency),
                    style: _amount(t),
                  ),
                  const SizedBox(height: 4),
                  VouchFlowStatusBadge(
                    label: rows[i].status,
                    tag: switch (rows[i].status) {
                      'paid' => 'tag-accent',
                      'pending' => 'tag-warn',
                      _ => 'tag-neutral',
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The default approval route, step by step, with a way into its settings.
class WorkflowPanel extends StatelessWidget {
  const WorkflowPanel({
    super.key,
    required this.workflow,
    required this.onManage,
  });

  final DashboardWorkflow? workflow;
  final VoidCallback onManage;

  static const _icons = {
    'request': PhosphorIconsRegular.filePlus,
    'sign': PhosphorIconsRegular.signature,
    'approve': PhosphorIconsRegular.sealCheck,
    'pay': PhosphorIconsRegular.wallet,
    'review': PhosphorIconsRegular.eye,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final sw = dashIsSw;
    final w = workflow;

    return DashPanel(
      title: 'dash.panel.workflow'.tr,
      trailing: DashLink(label: 'dashboard.manage'.tr, onTap: onManage),
      child: w == null || w.steps.isEmpty
          ? DashEmpty('dash.panel.noWorkflow'.tr)
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                children: [
                  for (var i = 0; i < w.steps.length; i++)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 32,
                            child: Column(
                              children: [
                                const SizedBox(height: 6),
                                DashIconTile(
                                  icon:
                                      _icons[w.steps[i].action] ??
                                      PhosphorIconsRegular.circle,
                                  color: t.primary,
                                  size: 32,
                                ),
                                if (i < w.steps.length - 1)
                                  Expanded(
                                    child: Container(
                                      width: 2,
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: t.primarySoftStrong,
                                        borderRadius: BorderRadius.circular(1),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      sw &&
                                              (w.steps[i].nameSw?.isNotEmpty ??
                                                  false)
                                          ? w.steps[i].nameSw!
                                          : w.steps[i].name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _title(t),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    dashTr(
                                      'dash.step.${w.steps[i].action}',
                                      w.steps[i].action,
                                    ),
                                    style: _meta(t),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class SubscriptionPanel extends StatelessWidget {
  const SubscriptionPanel({
    super.key,
    required this.subscription,
    required this.onManage,
  });

  final DashboardSubscription subscription;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final s = subscription;
    return DashPanel(
      title: 'dash.panel.subscription'.tr,
      trailing: DashLink(label: 'dashboard.manage'.tr, onTap: onManage),
      child: DashFacts([
        ('dash.panel.plan'.tr, s.plan ?? '—', false),
        (
          'dash.panel.status'.tr,
          dashTr('subscription.${s.status}', s.status),
          false,
        ),
        if (s.status == 'trial')
          ('dash.panel.trialEnds'.tr, dashDate(s.trialEndsAt), false)
        else
          ('dash.panel.renews'.tr, dashDate(s.renewsAt), false),
        if (s.daysRemaining != null)
          (
            'dash.panel.daysRemaining'.tr,
            '${s.daysRemaining}',
            false,
          ),
      ]),
    );
  }
}

/// The vouchers this head signed most recently.
class RecentlySignedPanel extends StatelessWidget {
  const RecentlySignedPanel({
    super.key,
    required this.rows,
    required this.onOpen,
  });

  final List<DashboardSigned> rows;
  final void Function(int id) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return DashPanel(
      title: 'dash.panel.recentlySigned'.tr,
      child: rows.isEmpty
          ? DashEmpty('dash.activity.empty'.tr)
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  _ListRow(
                    last: i == rows.length - 1,
                    onTap: () => onOpen(rows[i].id),
                    lead: DashIconTile(
                      icon: PhosphorIconsRegular.signature,
                      color: t.successStrong,
                    ),
                    title: Text(
                      rows[i].payee,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _title(t),
                    ),
                    meta: rows[i].number,
                    trailing: Text(rows[i].amountText, style: _amount(t)),
                  ),
              ],
            ),
    );
  }
}

/// The platform's newest tenants.
class RecentCompaniesPanel extends StatelessWidget {
  const RecentCompaniesPanel({
    super.key,
    required this.rows,
    required this.onOpen,
  });

  final List<DashboardCompany> rows;
  final void Function(int id) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return DashPanel(
      title: 'dashboard.recentCompanies'.tr,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _ListRow(
              last: i == rows.length - 1,
              onTap: () => onOpen(rows[i].id),
              lead: DashIconTile(
                icon: PhosphorIconsRegular.buildings,
                color: t.primary,
              ),
              title: Text(
                rows[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _title(t),
              ),
              meta: [
                ?rows[i].plan,
                '${rows[i].usersCount} ${'dashboard.users'.tr}',
                '${rows[i].vouchersCount} ${'dashboard.vouchers'.tr}',
              ].join(' · '),
              trailing: VouchFlowStatusBadge(
                label: rows[i].status,
                tag: switch (rows[i].status) {
                  'active' => 'tag-accent',
                  'trial' => 'tag-info',
                  _ => 'tag-accent-2',
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Seven months of voucher value as rounded columns; the current month
/// carries the brand gradient.
class VolumePanel extends StatelessWidget {
  const VolumePanel({super.key, required this.volume, required this.currency});

  final List<DashboardVolume> volume;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final max = volume.fold<double>(1, (m, v) => v.total > m ? v.total : m);
    final current = volume.where((v) => v.isCurrent).firstOrNull;

    return DashPanel(
      title: 'dashboard.voucherValue'.tr,
      trailing: current == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                dashCompactMoney(current.total, currency),
                style: _amount(t).copyWith(color: t.primaryText, fontSize: 15),
              ),
            ),
      child: Semantics(
        label: volume
            .map((v) => '${v.label}: ${dashMoney(v.total, currency)}')
            .join(', '),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < volume.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Tooltip(
                        message:
                            '${volume[i].label} · ${volume[i].count} · ${dashMoney(volume[i].total, currency)}',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: (volume[i].total / max).clamp(
                                    .04,
                                    1.0,
                                  ),
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 28,
                                    ),
                                    decoration: BoxDecoration(
                                      color: volume[i].isCurrent
                                          ? null
                                          : t.primarySoftStrong,
                                      gradient: volume[i].isCurrent
                                          ? LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                t.palette.hoverDark,
                                                t.palette.primaryLight,
                                              ],
                                            )
                                          : null,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              volume[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: VfType.meta.copyWith(
                                fontSize: 11.5,
                                color: volume[i].isCurrent ? t.text : t.muted,
                                fontWeight: volume[i].isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

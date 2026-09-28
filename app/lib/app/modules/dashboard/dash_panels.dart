import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../widgets/vf/vf.dart';
import 'dash_bits.dart';

/// "You have 3 vouchers waiting for your attention." — or a plain all-clear;
/// on the platform, the headline figures. The web's `.app-attn`.
class AttentionBanner extends StatelessWidget {
  const AttentionBanner({
    super.key,
    required DashboardBanner this.banner,
    this.onAction,
  }) : title = null,
       body = null;

  const AttentionBanner.plain({
    super.key,
    required this.title,
    required this.body,
  }) : banner = null,
       onAction = null;

  final DashboardBanner? banner;
  final VoidCallback? onAction;
  final String? title, body;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final b = banner;
    final pending = (b?.count ?? 0) > 0;
    final tone = b == null ? 'neutral' : (pending ? 'info' : 'ok');

    final (Color bg, Color edge, Color iconColour) = switch (tone) {
      'info' => (t.primarySoft, t.primary.withValues(alpha: .35), t.primary),
      'ok' => (
        t.successSoft,
        t.successStrong.withValues(alpha: .30),
        t.success,
      ),
      _ => (t.surface, t.border, t.text2),
    };
    final heading = b == null ? title ?? '' : dashTr(b.key, b.title, b.params);
    final text = b == null ? body ?? '' : dashTr(b.bodyKey, b.body);
    final icon = b == null
        ? PhosphorIconsRegular.globeHemisphereEast
        : pending
        ? PhosphorIconsRegular.bellRinging
        : PhosphorIconsRegular.checkCircle;

    return Semantics(
      liveRegion: b != null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          border: Border.all(color: edge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(VfSize.radiusM),
                    border: Border.all(color: t.border),
                  ),
                  child: Icon(icon, size: 20, color: iconColour),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        style: VfType.bodyStrong.copyWith(
                          color: t.text,
                          fontSize: 16,
                        ),
                      ),
                      if (text.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          text,
                          style: VfType.small.copyWith(
                            color: t.text2,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (b?.actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              VouchFlowButton(
                label: dashTr(b!.actionKey, b.actionLabel!),
                trailingIcon: PhosphorIconsRegular.arrowRight,
                compact: true,
                expand: true,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The note under the queue: acting moves a voucher on (or, for admins, what
/// "stalled" means). The web's `.app-panel-foot`.
class QueueFootnote extends StatelessWidget {
  const QueueFootnote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(PhosphorIconsRegular.info, size: 15, color: t.muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: VfType.meta.copyWith(color: t.muted, fontSize: 13),
            ),
          ),
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
    final dot = switch (row.action) {
      'approved' || 'paid' => t.successStrong,
      'signed' || 'submitted' || 'resubmitted' => t.primary,
      'rejected' => t.dangerStrong,
      'changes_requested' => t.warningStrong,
      _ => t.faint,
    };
    final meta = [
      ?row.amountText,
      dashRelative(DateTime.tryParse(row.at ?? '')?.toLocal()),
    ].join(' · ');

    return DashRow(
      last: last,
      onTap: () => onOpen(row.voucherId),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: you ? 'dash.activity.you'.tr : row.actor,
                        style: TextStyle(
                          color: t.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text:
                            ' ${dashTr('activity.${row.action}', row.actionLabel)} ',
                      ),
                      TextSpan(
                        text: row.voucherNumber,
                        style: TextStyle(
                          color: t.primaryText,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  style: VfType.body.copyWith(color: t.text2, height: 1.4),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: VfType.meta.copyWith(color: t.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
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
                  DashRow(
                    last: i == rows.length - 1,
                    onTap: () => onOpen(rows[i].id),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  VouchFlowStatusBadge(
                                    label: rows[i].status,
                                    tag: rows[i].status == 'trial'
                                        ? 'tag-info'
                                        : 'tag-accent-2',
                                  ),
                                  if (rows[i].plan != null)
                                    Text(
                                      rows[i].plan!,
                                      style: VfType.meta.copyWith(
                                        color: t.text2,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                rows[i].name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: VfType.bodyStrong.copyWith(
                                  color: t.text,
                                ),
                              ),
                              Text(
                                rows[i].note,
                                style: VfType.small.copyWith(color: t.muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${rows[i].usersCount} ${'dashboard.users'.tr}',
                          style: VfType.meta.copyWith(color: t.muted),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          PhosphorIconsRegular.caretRight,
                          size: 15,
                          color: t.faint,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The platform's latest subscription invoices; the web's table as rows.
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
    final figures = const [FontFeature.tabularFigures()];
    return DashPanel(
      title: 'dashboard.recentPayments'.tr,
      trailing: DashLink(label: 'dashboard.all'.tr, onTap: onAll),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            DashRow(
              last: i == rows.length - 1,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${'dashboard.invoice'.tr} ${rows[i].number}',
                          style: VfType.small.copyWith(
                            color: t.text,
                            fontWeight: FontWeight.w600,
                            fontFeatures: figures,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rows[i].company ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VfType.small.copyWith(color: t.text2),
                        ),
                        Text(
                          dashDate(rows[i].createdAt),
                          style: VfType.meta.copyWith(color: t.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        dashMoney(rows[i].total, rows[i].currency),
                        style: VfType.small.copyWith(
                          color: t.text,
                          fontWeight: FontWeight.w600,
                          fontFeatures: figures,
                        ),
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
    final name = w == null
        ? 'dash.panel.workflowSub'.tr
        : (sw && (w.nameSw?.isNotEmpty ?? false) ? w.nameSw! : w.name);

    return DashPanel(
      title: 'dash.panel.workflow'.tr,
      subtitle: name,
      trailing: DashLink(
        label: 'dash.panel.manageWorkflow'.tr,
        onTap: onManage,
      ),
      child: w == null || w.steps.isEmpty
          ? DashEmpty('dash.panel.noWorkflow'.tr)
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  for (var i = 0; i < w.steps.length; i++)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 28,
                            child: Column(
                              children: [
                                const SizedBox(height: 7),
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: t.primarySoft,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: t.primary.withValues(alpha: .35),
                                    ),
                                  ),
                                  child: Icon(
                                    _icons[w.steps[i].action] ??
                                        PhosphorIconsRegular.circle,
                                    size: 15,
                                    color: t.primary,
                                  ),
                                ),
                                if (i < w.steps.length - 1)
                                  Expanded(
                                    child: Container(width: 1, color: t.border),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 11),
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
                                      style: VfType.small.copyWith(
                                        color: t.text,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    dashTr(
                                      'dash.step.${w.steps[i].action}',
                                      w.steps[i].action,
                                    ),
                                    style: VfType.meta.copyWith(
                                      color: t.muted,
                                      fontSize: 13,
                                    ),
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
      trailing: DashLink(
        label: 'dash.panel.manageSubscription'.tr,
        onTap: onManage,
      ),
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
            '',
            dashTr('dash.panel.daysLeft', '${s.daysRemaining} days remaining', {
              'days': '${s.daysRemaining}',
            }),
            true,
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
    final figures = const [FontFeature.tabularFigures()];
    return DashPanel(
      title: 'dash.panel.recentlySigned'.tr,
      child: rows.isEmpty
          ? DashEmpty('dash.activity.empty'.tr)
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  DashRow(
                    last: i == rows.length - 1,
                    onTap: () => onOpen(rows[i].id),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rows[i].number,
                                style: VfType.body.copyWith(
                                  color: t.text,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: figures,
                                ),
                              ),
                              Text(
                                rows[i].payee,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: VfType.meta.copyWith(
                                  color: t.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          rows[i].amountText,
                          style: VfType.meta.copyWith(
                            color: t.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFeatures: figures,
                          ),
                        ),
                      ],
                    ),
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
            DashRow(
              last: i == rows.length - 1,
              onTap: () => onOpen(rows[i].id),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: VfType.body.copyWith(
                            color: t.text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          [
                            ?rows[i].plan,
                            '${rows[i].usersCount} ${'dashboard.users'.tr}',
                            '${rows[i].vouchersCount} ${'dashboard.vouchers'.tr}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VfType.meta.copyWith(
                            color: t.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  VouchFlowStatusBadge(
                    label: rows[i].status,
                    tag: switch (rows[i].status) {
                      'active' => 'tag-accent',
                      'trial' => 'tag-info',
                      _ => 'tag-accent-2',
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

/// Seven months of voucher value as quiet single-colour columns; the current
/// month is emphasised.
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
      subtitle: 'dashboard.last7Months'.tr,
      trailing: current == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                dashCompactMoney(current.total, currency),
                style: VfType.bodyStrong.copyWith(
                  color: t.text,
                  fontSize: 16,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
      child: Semantics(
        label: volume
            .map((v) => '${v.label}: ${dashMoney(v.total, currency)}')
            .join(', '),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 132,
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
                                    .03,
                                    1.0,
                                  ),
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 30,
                                    ),
                                    decoration: BoxDecoration(
                                      color: volume[i].isCurrent
                                          ? t.primary
                                          : t.primarySoftStrong,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(VfSize.radiusXs),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              volume[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: VfType.meta.copyWith(
                                fontSize: 12,
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

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../shell/shell_page.dart';
import '../../widgets/common.dart';
import '../vouchers/voucher_card.dart';

/// Translates a dashboard key from the API, filling `@name` placeholders from
/// [params]. An unknown key falls back to the English text the API sent.
String dashTr(
  String? key,
  String fallback, [
  Map<String, String> params = const {},
]) {
  if (key == null || key.isEmpty) return fallback;
  final text = params.isEmpty ? key.tr : key.trParams(params);
  return text == key ? fallback : text;
}

class DashboardController extends GetxController {
  final repo = Get.find<VoucherRepository>();
  final session = Get.find<SessionService>();

  final data = Rxn<DashboardData>();
  final loading = true.obs;
  final error = RxnString();

  /// Where the attention banner's button scrolls to.
  final queueKey = GlobalKey();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    error.value = null;
    try {
      data.value = await repo.dashboard();
      await session.refreshUnread();
    } on ApiException catch (e) {
      error.value = e.message;
    } catch (_) {
      error.value = 'state.offline'.tr;
    } finally {
      loading.value = false;
    }
  }

  void showQueue() {
    final target = queueKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }
}

/// Icon per figure, by the figure's stable key.
const _statIcons = <String, String>{
  'dash.stat.myVouchers': 'receipt',
  'dash.stat.pending': 'hourglass',
  'dash.stat.approved': 'seal',
  'dash.stat.rejected': 'undo',
  'dash.stat.paidVouchers': 'check',
  'dash.stat.amountRaised': 'coins',
  'dash.stat.awaitingSignature': 'signature',
  'dash.stat.signedThisMonth': 'signature',
  'dash.stat.deptVouchersThisMonth': 'receipt',
  'dash.stat.deptValue': 'coins',
  'dash.stat.deptExpenses': 'coins',
  'dash.stat.awaitingApproval': 'seal',
  'dash.stat.approvedThisMonth': 'check',
  'dash.stat.rejectedThisMonth': 'undo',
  'dash.stat.totalValue': 'coins',
  'dash.stat.awaitingPayment': 'wallet',
  'dash.stat.pendingPayments': 'bank',
  'dash.stat.paidThisMonth': 'money',
  'dash.stat.activeUsers': 'chart',
  'dash.stat.submittedVouchers': 'receipt',
  'dash.stat.inWorkflow': 'hourglass',
  'dash.stat.approvedIncludingPaid': 'seal',
  'dash.stat.valueThisMonth': 'chart',
  'dash.stat.avgApprovalTime': 'hourglass',
};

class DashboardTab extends GetView<DashboardController> {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = Get.find<SessionService>();

    return Obx(() {
      if (controller.loading.value && controller.data.value == null) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.error.value != null && controller.data.value == null) {
        return ErrorView(
          message: controller.error.value!,
          onRetry: controller.load,
        );
      }

      final d = controller.data.value!;
      final company = session.company.value;
      final view = d.view.isNotEmpty ? d.view : _viewFor(session.me);
      final firstName = session.me.name.split(' ').first;
      final greeting = dashTr('greeting.${d.greeting}', d.greeting);

      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
          children: [
            if (company != null && !company.isUsable)
              _Banner(
                icon: Icons.warning_amber_outlined,
                title: 'state.expired'.tr,
                body: 'state.expiredBody'.tr,
                colour: VfColors.bad,
              ),
            if (company != null &&
                company.isUsable &&
                company.status == 'trial')
              _Banner(
                icon: Icons.schedule,
                title: 'dash.panel.trialEnds'.tr,
                body:
                    '${dashTr('dash.trialBanner', '${company.daysRemaining ?? 0} days remaining on your ${company.plan?.name ?? ''} trial.', {'days': '${company.daysRemaining ?? 0}', 'plan': company.plan?.name ?? ''})} · ${Fmt.date(company.trialEndsAt)}',
                colour: VfColors.warn,
              ),

            Text(
              '$greeting, $firstName',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              dashTr('dash.intro', "Here's your voucher activity at a glance."),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),

            if (d.banner != null)
              _AttentionCard(banner: d.banner!, onAction: controller.showQueue)
            else
              _AttentionCard.plain(title: d.headline, body: d.sub),
            const SizedBox(height: 20),

            // A fixed aspect ratio clips the moment a label wraps to two lines or
            // the user raises their text size. Wrap sizes to content instead, so
            // the tiles grow rather than overflow.
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 18.0;
                final width = (constraints.maxWidth - gap) / 2;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: d.stats
                      .map(
                        (s) => SizedBox(
                          width: width,
                          child: StatTile(
                            label: dashTr(s.key, s.label, s.params),
                            value: s.value,
                            sub: s.subKey == null
                                ? s.sub
                                : dashTr(s.subKey, s.sub, s.subParams),
                            icon: _statIcons[s.key] ?? s.icon,
                            trend: s.trend,
                            up: s.up,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),

            /* The queue, and only the queue. Acting on a voucher moves it to
               whoever is next, so it leaves this list. When it is empty the
               banner above already says so — no second empty message. */
            if (d.queue.isNotEmpty) ...[
              const SizedBox(height: 26),
              SectionHeader(
                key: controller.queueKey,
                title: dashTr('dash.queue.$view', 'queue.title'.tr),
                trailing: d.queueTotalText.isEmpty
                    ? null
                    : Text(d.queueTotalText, style: theme.textTheme.bodySmall),
              ),
              if (view == 'approver' && d.queue.length > 1) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Get.toNamed(Routes.bulkApprove);
                      await controller.load();
                    },
                    icon: const Icon(Icons.done_all, size: 18),
                    label: Text('bulk.title'.tr),
                  ),
                ),
              ],
              ...d.queue.map(
                (v) => VoucherCard(voucher: v, onReturn: controller.load),
              ),
              const SizedBox(height: 6),
              VfNote(
                view == 'admin' ? 'queue.stalledNote'.tr : 'queue.note'.tr,
              ),
            ],

            for (final panel in d.panels.entries)
              _PanelSection(panelKey: panel.key, lines: panel.value),

            if (view != 'platform') ...[
              const SizedBox(height: 26),
              SectionHeader(
                title: dashTr(d.activityKey, d.activityLabel),
                trailing: TextButton(
                  onPressed: () => Get.find<ShellController>().index.value = 1,
                  child: Text(
                    view == 'employee'
                        ? 'dash.panel.voucherHistory'.tr
                        : 'dash.panel.viewAll'.tr,
                  ),
                ),
              ),
              if (d.activity.isEmpty)
                Text('dash.activity.empty'.tr, style: theme.textTheme.bodySmall)
              else
                ...d.activity.map(
                  (row) => _ActivityRow(row: row, selfId: session.me.id),
                ),
            ],

            if (d.queue.isEmpty && session.me.canCreateVouchers) ...[
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Get.toNamed(
                    Routes.createVoucher,
                  )?.then((_) => controller.load()),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('voucher.create'.tr),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  static String _viewFor(AppUser me) {
    if (me.isAdmin) return 'admin';
    if (me.isCashier) return 'cashier';
    if (me.isEmployee) return 'employee';
    return me.role == 'hod' ? 'hod' : 'approver';
  }
}

/// "You have 3 vouchers waiting for your attention." — or the all-clear.
class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required DashboardBanner this.banner, this.onAction})
    : title = null,
      body = null;

  const _AttentionCard.plain({required this.title, required this.body})
    : banner = null,
      onAction = null;

  final DashboardBanner? banner;
  final VoidCallback? onAction;
  final String? title, body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = banner;
    final pending = (b?.count ?? 0) > 0;
    final colour = b == null
        ? context.vfMuted
        : (pending ? context.vfAccent : VfColors.ok);

    final heading = b == null ? title ?? '' : dashTr(b.key, b.title, b.params);
    final text = b == null ? body ?? '' : dashTr(b.bodyKey, b.body);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .10),
        border: Border.all(color: colour.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                pending
                    ? Icons.notifications_active_outlined
                    : Icons.check_circle_outline,
                size: 22,
                color: colour,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(heading, style: theme.textTheme.titleSmall),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(text, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (pending && b?.actionLabel != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_downward, size: 18),
                label: Text(dashTr(b!.actionKey, b.actionLabel!)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A role's side panel: recently signed, department spending, payment
/// totals, the workflow route, or the subscription.
class _PanelSection extends StatelessWidget {
  const _PanelSection({required this.panelKey, required this.lines});

  final String panelKey;
  final List<DashboardLine> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sw = Get.locale?.languageCode == 'sw';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 26),
        SectionHeader(title: dashTr(panelKey, panelKey)),
        if (lines.isEmpty)
          Text('dash.activity.empty'.tr, style: theme.textTheme.bodySmall)
        else
          Container(
            decoration: BoxDecoration(
              color: context.vfElev1,
              border: Border.all(color: context.vfLine),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (var i = 0; i < lines.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      border: i == lines.length - 1
                          ? null
                          : Border(bottom: BorderSide(color: context.vfLine)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dashTr(
                                  lines[i].label,
                                  sw && lines[i].labelSw != null
                                      ? lines[i].labelSw!
                                      : lines[i].label,
                                ),
                                style: theme.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (lines[i].meta != null &&
                                  lines[i].meta!.isNotEmpty)
                                Text(
                                  lines[i].meta!,
                                  style: theme.textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          dashTr(lines[i].value, lines[i].value),
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "{actor} {action} {voucher}" with the amount and how long ago.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.row, required this.selfId});

  final DashboardActivity row;
  final int selfId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actor = row.actorId == selfId ? 'dash.activity.you'.tr : row.actor;
    final colour = switch (row.action) {
      'approved' || 'paid' => VfColors.ok,
      'rejected' => VfColors.bad,
      'changes_requested' || 'part_paid' => VfColors.warn,
      _ => context.vfAccent,
    };

    return InkWell(
      onTap: () => Get.toNamed(Routes.voucher, arguments: row.voucherId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Icon(Icons.circle, size: 8, color: colour),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$actor ${dashTr('activity.${row.action}', row.actionLabel)} ${row.voucherNumber}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    [
                      if (row.amountText != null) row.amountText!,
                      Fmt.relative(DateTime.tryParse(row.at ?? '')?.toLocal()),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
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

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.title,
    required this.body,
    required this.colour,
  });

  final IconData icon;
  final String title, body;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: .10),
      border: Border.all(color: colour.withValues(alpha: .5)),
      borderRadius: BorderRadius.circular(2),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colour),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              Text(body, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

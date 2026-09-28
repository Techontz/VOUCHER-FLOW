import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/dashboard_models.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/dashboard_repository.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../shell/shell_page.dart';
import 'dash_bits.dart';
import 'dash_panels.dart';
import 'queue_row.dart';

export 'dash_bits.dart' show dashTr;

/// The dashboard: a greeting, one plain sentence about what is waiting on
/// you, the figures for your role, and the work itself.
///
/// What each role sees — and every number on it — is decided by the backend
/// from the vouchers that user may see. This screen decides only how it
/// reads, translating each figure by its stable key and falling back to the
/// English text the API sent.
class DashboardController extends GetxController {
  final repo = DashboardRepository.to;
  final session = Get.find<SessionService>();

  final data = Rxn<DashboardData>();
  final workflows = Rxn<List<QueueWorkflow>>();
  final loading = true.obs;
  final error = RxnString();

  /// Where the attention banner's button and the actionable figures scroll.
  final queueKey = GlobalKey();

  Worker? _localeWorker;
  int _generation = 0;

  @override
  void onInit() {
    super.onInit();
    load();
    // The API words its fallbacks in the request's language (web: reload on
    // locale change).
    _localeWorker = ever(session.locale, (_) => load());
  }

  @override
  void onClose() {
    _localeWorker?.dispose();
    super.onClose();
  }

  Future<void> load() async {
    final generation = ++_generation;
    error.value = null;
    try {
      final next = await repo.dashboard();
      if (generation != _generation) return;
      data.value = next;
      unawaited(session.refreshUnread());
      unawaited(_loadRoutes(next));
    } on ApiException catch (e) {
      if (generation == _generation) error.value = e.message;
    } catch (_) {
      if (generation == _generation) error.value = 'state.offline'.tr;
    } finally {
      if (generation == _generation) loading.value = false;
    }
  }

  /// The company's routes, for each queued voucher's progress. Progress is an
  /// enhancement on a list; a failure here never breaks the dashboard.
  Future<void> _loadRoutes(DashboardData d) async {
    final companyId = session.company.value?.id;
    if (companyId == null || d.queue.isEmpty) return;
    try {
      workflows.value = await repo.workflows(companyId);
    } catch (_) {
      workflows.value = const [];
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

  void go(String href) => Get.find<ShellController>().go(href);

  Future<void> openVoucher(int id) async {
    await Get.toNamed(Routes.voucher, arguments: id);
    await load();
  }

  Future<void> openCompany(int id) async {
    await Get.toNamed(Routes.platformCompany, arguments: id);
    await load();
  }

  /// The dashboard a role gets when an older payload carries no `view`.
  String viewFor(DashboardData d) {
    if (d.view.isNotEmpty) return d.view;
    return switch (session.user.value?.role) {
      'hod' => 'hod',
      'manager' || 'ceo' || 'director' || 'finance' => 'approver',
      'cashier' => 'cashier',
      'company_admin' => 'admin',
      'super_admin' => 'platform',
      _ => 'employee',
    };
  }
}

typedef _Look = (IconData, VfTone);

/// Icon and tone per figure, by the figure's stable key — so a figure keeps
/// its look whichever dashboard it appears on. Only the numbers that ask for
/// action are coloured.
const _looks = <String, _Look>{
  'dash.stat.myVouchers': (PhosphorIconsRegular.receipt, VfTone.primary),
  'dash.stat.pending': (PhosphorIconsRegular.hourglassMedium, VfTone.info),
  'dash.stat.approved': (PhosphorIconsRegular.sealCheck, VfTone.ok),
  'dash.stat.rejected': (PhosphorIconsRegular.xCircle, VfTone.bad),
  'dash.stat.paidVouchers': (PhosphorIconsRegular.checkCircle, VfTone.ok),
  'dash.stat.amountRaised': (PhosphorIconsRegular.coins, VfTone.primary),
  'dash.stat.awaitingSignature': (PhosphorIconsRegular.signature, VfTone.info),
  'dash.stat.signedThisMonth': (PhosphorIconsRegular.penNib, VfTone.ok),
  'dash.stat.deptVouchersThisMonth': (
    PhosphorIconsRegular.files,
    VfTone.primary,
  ),
  'dash.stat.deptValue': (PhosphorIconsRegular.coins, VfTone.primary),
  'dash.stat.deptExpenses': (PhosphorIconsRegular.buildings, VfTone.primary),
  'dash.stat.awaitingApproval': (PhosphorIconsRegular.sealCheck, VfTone.info),
  'dash.stat.approvedThisMonth': (PhosphorIconsRegular.checkCircle, VfTone.ok),
  'dash.stat.rejectedThisMonth': (PhosphorIconsRegular.xCircle, VfTone.bad),
  'dash.stat.totalValue': (PhosphorIconsRegular.coins, VfTone.primary),
  'dash.stat.awaitingPayment': (PhosphorIconsRegular.wallet, VfTone.info),
  'dash.stat.pendingPayments': (PhosphorIconsRegular.bank, VfTone.primary),
  'dash.stat.paidThisMonth': (PhosphorIconsRegular.money, VfTone.ok),
  'dash.stat.activeUsers': (PhosphorIconsRegular.usersThree, VfTone.primary),
  'dash.stat.submittedVouchers': (PhosphorIconsRegular.receipt, VfTone.primary),
  'dash.stat.inWorkflow': (PhosphorIconsRegular.arrowsClockwise, VfTone.info),
  'dash.stat.approvedIncludingPaid': (
    PhosphorIconsRegular.sealCheck,
    VfTone.ok,
  ),
  'dash.stat.valueThisMonth': (
    PhosphorIconsRegular.chartLineUp,
    VfTone.primary,
  ),
  'dash.stat.avgApprovalTime': (PhosphorIconsRegular.timer, VfTone.primary),
  'dash.stat.totalCompanies': (PhosphorIconsRegular.buildings, VfTone.primary),
  'dash.stat.monthlyRevenue': (
    PhosphorIconsRegular.currencyCircleDollar,
    VfTone.ok,
  ),
  'dash.stat.trailingRevenue': (
    PhosphorIconsRegular.chartLineUp,
    VfTone.primary,
  ),
  'dash.stat.totalUsers': (PhosphorIconsRegular.usersThree, VfTone.primary),
  'dash.stat.totalVouchers': (PhosphorIconsRegular.receipt, VfTone.primary),
  'dash.stat.pendingApprovedRejected': (
    PhosphorIconsRegular.stack,
    VfTone.primary,
  ),
  'dash.stat.needsAttention': (PhosphorIconsRegular.warningCircle, VfTone.warn),
  'dash.stat.outstanding': (PhosphorIconsRegular.receipt, VfTone.primary),
};

class DashboardTab extends GetView<DashboardController> {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final d = controller.data.value;
      if (d == null && controller.error.value != null) {
        return VouchFlowPageBody(
          onRefresh: controller.load,
          children: [
            VouchFlowErrorState(
              message: controller.error.value!,
              onRetry: controller.load,
              retryLabel: 'action.retry'.tr,
            ),
          ],
        );
      }
      if (d == null) return const _Skeleton();
      // Read so progress redraws once routes arrive.
      final routes = controller.workflows.value;
      // Touched here so Obx tracks them; _content reads them inside the
      // LayoutBuilder, where reads are not tracked.
      controller.session.user.value;
      controller.session.company.value;
      controller.session.locale.value;
      return LayoutBuilder(
        builder: (context, box) => VouchFlowPageBody(
          onRefresh: controller.load,
          padding: EdgeInsets.fromLTRB(
            box.maxWidth >= 700 ? 24 : VfSize.pagePad,
            20,
            box.maxWidth >= 700 ? 24 : VfSize.pagePad,
            32,
          ),
          children: _content(context, d, routes, box.maxWidth),
        ),
      );
    });
  }

  List<Widget> _content(
    BuildContext context,
    DashboardData d,
    List<QueueWorkflow>? routes,
    double width,
  ) {
    final session = controller.session;
    final user = session.user.value;
    final company = session.company.value;
    final view = controller.viewFor(d);
    final isPlatform = view == 'platform';
    final canCreate = !isPlatform && view != 'cashier';
    final expiring =
        company != null &&
        company.status == 'trial' &&
        (company.daysRemaining ?? 99) <= 7;

    final firstName = (user?.name ?? '').split(' ').first;
    final greeting = dashTr('greeting.${d.greeting}', d.greeting);
    final gap = const SizedBox(height: 16);

    final main = <Widget>[
      if (!isPlatform && d.queue.isNotEmpty)
        KeyedSubtree(key: controller.queueKey, child: _queue(d, view, routes)),
      if (!isPlatform && d.activity != null)
        ActivityPanel(
          title: dashTr(d.activityKey, d.activityLabel),
          rows: d.activity!,
          selfId: user?.id,
          onOpen: controller.openVoucher,
          link: view == 'employee'
              ? (
                  'dash.panel.voucherHistory'.tr,
                  () => controller.go('/vouchers'),
                )
              : ('dash.panel.viewReports'.tr, () => controller.go('/reports')),
        ),
      if (d.attention != null)
        AttentionCompaniesPanel(
          rows: d.attention!,
          onAll: () => controller.go('/platform/companies'),
          onOpen: controller.openCompany,
        ),
      if (isPlatform && (d.recentPayments?.isNotEmpty ?? false))
        RecentPaymentsPanel(
          rows: d.recentPayments!,
          onAll: () => controller.go('/platform/payments'),
        ),
    ];

    final currency = company?.currency ?? 'TZS';
    final aside = <Widget>[
      if (view == 'admin' &&
          (d.overview != null || d.hasWorkflow || d.subscription != null)) ...[
        if (d.overview != null)
          DashPanel(
            title: 'dash.panel.companyOverview'.tr,
            child: DashFacts([
              (
                'dash.panel.activeUsers'.tr,
                '${d.overview!.activeUsers}',
                false,
              ),
              (
                'dash.panel.departments'.tr,
                '${d.overview!.departments}',
                false,
              ),
            ]),
          ),
        WorkflowPanel(
          workflow: d.workflow,
          onManage: () => controller.go('/settings'),
        ),
        if (d.subscription != null)
          SubscriptionPanel(
            subscription: d.subscription!,
            onManage: () => controller.go('/subscription'),
          ),
      ],
      if (view == 'hod' && d.recentlySigned != null)
        RecentlySignedPanel(
          rows: d.recentlySigned!,
          onOpen: controller.openVoucher,
        ),
      if (view == 'cashier' && d.paymentTotals != null)
        DashPanel(
          title: 'dash.panel.paymentTotals'.tr,
          subtitle: 'dash.panel.paymentTotalsSub'.tr,
          child: DashFacts([
            (
              '${'dash.panel.paidTotal'.tr} · ${d.paymentTotals!.paid.count}',
              d.paymentTotals!.paid.totalText,
              false,
            ),
            (
              '${'dash.panel.bank'.tr} · ${d.paymentTotals!.bank.count}',
              d.paymentTotals!.bank.totalText,
              false,
            ),
            (
              '${'dash.panel.cash'.tr} · ${d.paymentTotals!.cash.count}',
              d.paymentTotals!.cash.totalText,
              false,
            ),
          ]),
        ),
      if (d.byStage?.isNotEmpty ?? false)
        DashPanel(
          title: 'dashboard.byStage'.tr,
          child: DashBars([
            for (final r in d.byStage!)
              (r.name, r.count, dashCompactMoney(r.total, currency), r.share),
          ]),
        ),
      if (d.volume?.isNotEmpty ?? false)
        VolumePanel(volume: d.volume!, currency: currency),
      if (d.byDepartment != null &&
          (view == 'approver' || d.byDepartment!.isNotEmpty))
        DashPanel(
          title: 'dash.panel.deptSpending'.tr,
          subtitle: view == 'approver'
              ? 'dash.panel.deptSpendingMonth'.tr
              : 'dash.panel.deptSpendingAll'.tr,
          child: d.byDepartment!.isEmpty
              ? DashEmpty('dash.activity.empty'.tr)
              : DashBars([
                  for (final r in d.byDepartment!.take(6))
                    (
                      r.name,
                      r.count,
                      dashCompactMoney(r.total, currency),
                      r.share,
                    ),
                ]),
        ),
      if (isPlatform && (d.recentCompanies?.isNotEmpty ?? false))
        RecentCompaniesPanel(
          rows: d.recentCompanies!,
          onOpen: controller.openCompany,
        ),
      if (view == 'employee')
        VouchFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VouchFlowButton(
                label: 'dash.panel.voucherHistory'.tr,
                icon: PhosphorIconsRegular.clockCounterClockwise,
                variant: VfButtonVariant.secondary,
                expand: true,
                onPressed: () => controller.go('/vouchers'),
              ),
              const SizedBox(height: 10),
              VouchFlowButton(
                label: 'dash.panel.viewReports'.tr,
                icon: PhosphorIconsRegular.chartLine,
                variant: VfButtonVariant.secondary,
                expand: true,
                onPressed: () => controller.go('/reports'),
              ),
            ],
          ),
        ),
    ];

    List<Widget> spaced(List<Widget> items) => [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) gap, items[i]],
    ];

    final wide = width >= 1000;

    return [
      if (company != null && !company.isUsable) ...[
        VouchFlowAlert(
          tone: VfTone.bad,
          icon: PhosphorIconsRegular.warningCircle,
          title: 'dashboard.expired'.tr,
          message: 'dashboard.expiredBody'.tr,
          action: VouchFlowButton(
            label: 'dashboard.payNow'.tr,
            compact: true,
            onPressed: () => controller.go('/subscription'),
          ),
        ),
        gap,
      ],
      if (expiring && company.isUsable) ...[
        VouchFlowAlert(
          tone: VfTone.warn,
          icon: PhosphorIconsRegular.clock,
          title: '${'dashboard.trialEnds'.tr} ${dashDate(company.trialEndsAt)}',
          message: dashTr(
            'dash.trialBanner',
            '${company.daysRemaining} days remaining on your ${company.plan?.name ?? ''} trial.',
            {
              'days': '${company.daysRemaining ?? 0}',
              'plan': company.plan?.name ?? '',
            },
          ),
          action: VouchFlowButton(
            label: 'dashboard.changePlan'.tr,
            compact: true,
            variant: VfButtonVariant.secondary,
            onPressed: () => controller.go('/subscription'),
          ),
        ),
        gap,
      ],

      VouchFlowPageHeader(
        title: firstName.isEmpty ? greeting : '$greeting, $firstName',
        subtitle: isPlatform
            ? dashTr('dash.introPlatform', "Here's the platform at a glance.")
            : dashTr('dash.intro', "Here's your voucher activity at a glance."),
      ),
      const SizedBox(height: 16),
      _headActions(isPlatform, canCreate, width),
      const SizedBox(height: 20),

      if (d.banner != null) ...[
        AttentionBanner(
          banner: d.banner!,
          onAction: d.queue.isEmpty ? null : controller.showQueue,
        ),
        gap,
      ] else if (isPlatform) ...[
        AttentionBanner.plain(title: d.headline, body: d.sub),
        gap,
      ],

      _figures(context, d, isPlatform, width),
      const SizedBox(height: 20),

      if (wide && main.isNotEmpty && aside.isNotEmpty)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: spaced(main))),
            const SizedBox(width: 24),
            SizedBox(width: 360, child: Column(children: spaced(aside))),
          ],
        )
      else
        ...spaced([...main, ...aside]),
    ];
  }

  Widget _headActions(bool isPlatform, bool canCreate, double width) {
    if (isPlatform) {
      return VouchFlowButton(
        label: 'nav.companies'.tr,
        icon: PhosphorIconsRegular.buildings,
        expand: width < 700,
        onPressed: () => controller.go('/platform/companies'),
      );
    }
    final reports = VouchFlowButton(
      label: 'nav.reports'.tr,
      icon: PhosphorIconsRegular.chartLine,
      variant: VfButtonVariant.secondary,
      expand: width < 700,
      onPressed: () => controller.go('/reports'),
    );
    if (!canCreate) {
      return Align(alignment: Alignment.centerLeft, child: reports);
    }
    final create = VouchFlowButton(
      label: 'dashboard.createVoucher'.tr,
      icon: PhosphorIconsRegular.plus,
      expand: width < 700,
      onPressed: () => controller.go('/vouchers/new'),
    );
    if (width >= 700) {
      return Wrap(spacing: 10, runSpacing: 10, children: [reports, create]);
    }
    return Row(
      children: [
        Expanded(flex: 4, child: reports),
        const SizedBox(width: 12),
        Expanded(flex: 5, child: create),
      ],
    );
  }

  Widget _figures(
    BuildContext context,
    DashboardData d,
    bool isPlatform,
    double width,
  ) {
    final count = d.stats.length;
    final cols = width < 560
        ? 2
        : (count % 4 == 0 && width >= 720)
        ? 4
        : 3;
    final tiles = <Widget>[];
    for (var i = 0; i < d.stats.length; i++) {
      final s = d.stats[i];
      final look =
          _looks[s.key] ?? (PhosphorIconsRegular.chartBar, VfTone.primary);
      final value = double.tryParse(s.value.replaceAll(',', '')) ?? 0;
      final actionable =
          look.$2 == VfTone.info &&
          value > 0 &&
          d.queue.isNotEmpty &&
          !isPlatform;
      final sub = s.subKey == null
          ? s.sub
          : dashTr(s.subKey, s.sub, s.subParams);
      final trend = s.trend == null
          ? null
          : '${s.up == true ? '↑' : '↓'} ${s.trend}';
      tiles.add(
        VouchFlowStatCard(
          label: dashTr(s.key, s.label, s.params),
          // Unbreakable, so a long figure scales rather than wraps.
          value: s.value.replaceAll(' ', '\u00A0'),
          sub: [?trend, if (sub.isNotEmpty) sub].join(' · ').nullIfEmpty,
          icon: look.$1,
          tone: look.$2,
          onTap: actionable ? controller.showQueue : null,
        ),
      );
    }

    const spacing = 12.0;
    return Semantics(
      label: dashTr('dash.keyFigures', 'Key figures'),
      container: true,
      child: Column(
        children: [
          for (var r = 0; r < tiles.length; r += cols) ...[
            if (r > 0) const SizedBox(height: spacing),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < cols; c++) ...[
                    if (c > 0) const SizedBox(width: spacing),
                    Expanded(
                      child: r + c < tiles.length
                          ? tiles[r + c]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _queue(DashboardData d, String view, List<QueueWorkflow>? routes) {
    final sw = dashIsSw;
    return DashPanel(
      title: dashTr('dash.queue.$view', 'dashboard.needsYourAction'.tr),
      count: d.queue.length,
      below: _queueHeadLine(d, view),
      footer: QueueFootnote(
        view == 'admin'
            ? 'dashboard.stalledNote'.tr
            : 'dashboard.clearedNote'.tr,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < d.queue.length; i++)
            QueueRow(
              voucher: d.queue[i],
              last: i == d.queue.length - 1,
              progress: deriveQueueProgress(
                status: d.queue[i].status,
                amount: d.queue[i].amount,
                workflowId: d.queueRoutes[i].workflowId,
                currentStepPosition: d.queueRoutes[i].currentStepPosition,
                workflows: routes,
                sw: sw,
              ),
              onOpen: () => controller.openVoucher(d.queue[i].id),
            ),
        ],
      ),
    );
  }
}

Widget _queueHeadLine(DashboardData d, String view) {
  final total = d.queueTotalText;
  final bulk = view == 'approver' && d.queue.length > 1;
  if ((total == null || total.isEmpty) && !bulk) return const SizedBox.shrink();
  return Builder(
    builder: (context) {
      final t = context.vf;
      return Padding(
        padding: const EdgeInsets.only(top: 2, right: 8),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            if (total != null && total.isNotEmpty)
              Text.rich(
                TextSpan(
                  text: '${'dashboard.total'.tr} ',
                  children: [
                    TextSpan(
                      text: total,
                      style: TextStyle(
                        color: t.text,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                style: VfType.small.copyWith(color: t.muted),
              ),
            if (bulk)
              VouchFlowButton(
                label: 'dashboard.approveSelected'.tr,
                icon: PhosphorIconsRegular.checks,
                variant: VfButtonVariant.ghost,
                compact: true,
                onPressed: () => Get.find<ShellController>().go('/approvals'),
              ),
          ],
        ),
      );
    },
  );
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// The shape of the dashboard, so the page does not jump when data arrives.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    Widget bar(double w, double h) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: w,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: t.surface3,
          borderRadius: BorderRadius.circular(VfSize.radiusS),
        ),
      ),
    );
    return VouchFlowPageBody(
      children: [
        Semantics(
          label: 'dashboard.loading'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(.7, 26),
              const SizedBox(height: 10),
              bar(.6, 14),
              const SizedBox(height: 22),
            ],
          ),
        ),
        const VouchFlowLoadingState(rows: 1, rowHeight: 64),
        const VouchFlowLoadingState(rows: 2, rowHeight: 120),
        const VouchFlowLoadingState(rows: 2, rowHeight: 220),
      ],
    );
  }
}

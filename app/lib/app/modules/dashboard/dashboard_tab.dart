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
import '../shell/nav.dart';
import '../shell/shell_page.dart';
import 'dash_bits.dart';
import 'dash_panels.dart';
import 'queue_row.dart';

export 'dash_bits.dart' show dashTr;

/// Home: a greeting, one hero figure for what is waiting on you, round
/// shortcuts, compact figures for your role, and the work itself.
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
      final unread = controller.session.unread.value;
      return LayoutBuilder(
        builder: (context, box) => VouchFlowPageBody(
          onRefresh: controller.load,
          padding: EdgeInsets.fromLTRB(
            box.maxWidth >= 700 ? 24 : VfSize.pagePad,
            20,
            box.maxWidth >= 700 ? 24 : VfSize.pagePad,
            32,
          ),
          children: _content(context, d, routes, box.maxWidth, unread),
        ),
      );
    });
  }

  List<Widget> _content(
    BuildContext context,
    DashboardData d,
    List<QueueWorkflow>? routes,
    double width,
    int unread,
  ) {
    final t = context.vf;
    final session = controller.session;
    final user = session.user.value;
    final company = session.company.value;
    final view = controller.viewFor(d);
    final isPlatform = view == 'platform';
    final expiring =
        company != null &&
        company.status == 'trial' &&
        (company.daysRemaining ?? 99) <= 7;

    final firstName = (user?.name ?? '').split(' ').first;
    final greeting = dashTr('greeting.${d.greeting}', d.greeting);
    const gap = SizedBox(height: 24);

    // The platform's hero is its monthly revenue; that figure then leaves
    // the tiles so it is not shown twice.
    final heroStat = isPlatform
        ? (d.stats.firstWhereOrNull(
                (s) => s.key == 'dash.stat.monthlyRevenue',
              ) ??
              d.stats.firstOrNull)
        : null;
    final stats = d.stats.where((s) => s != heroStat).toList();

    final main = <Widget>[
      if (!isPlatform && d.activity != null)
        ActivityPanel(
          title: dashTr(d.activityKey, d.activityLabel),
          rows: d.activity!,
          selfId: user?.id,
          onOpen: controller.openVoucher,
          link: (
            'dash.panel.viewAll'.tr,
            view == 'employee'
                ? () => controller.go('/vouchers')
                : () => controller.go('/reports'),
          ),
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
    ];

    List<Widget> spaced(List<Widget> items) => [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) gap, items[i]],
    ];

    final wide = width >= 1000;

    return [
      if (company != null && !company.isUsable) ...[
        DashAlertRow(
          tone: VfTone.bad,
          icon: PhosphorIconsRegular.warningCircle,
          text: 'dashboard.expired'.tr,
          trailing: 'dashboard.payNow'.tr,
          onTap: () => controller.go('/subscription'),
        ),
        const SizedBox(height: 16),
      ],
      if (expiring && company.isUsable) ...[
        DashAlertRow(
          tone: VfTone.warn,
          icon: PhosphorIconsRegular.clock,
          text: '${'dashboard.trialEnds'.tr} ${dashDate(company.trialEndsAt)}',
          onTap: () => controller.go('/subscription'),
        ),
        const SizedBox(height: 16),
      ],

      // Greeting: a quiet line, then the name, large.
      Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: VfType.body.copyWith(
                color: t.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (firstName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                firstName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VfType.pageTitle.copyWith(color: t.text, fontSize: 30),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),

      _hero(d, view, heroStat),
      const SizedBox(height: 22),

      // What is waiting on this person comes first, each with its action.
      if (!isPlatform && d.queue.isNotEmpty) ...[
        KeyedSubtree(key: controller.queueKey, child: _queue(d, view, routes)),
        gap,
      ],

      _quickActions(user?.role ?? 'employee', unread),
      gap,

      if (stats.isNotEmpty) ...[_figures(d, stats, isPlatform, width), gap],

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

  /// The one figure that matters: what is waiting on this person — or, on
  /// the platform, this month's revenue.
  Widget _hero(DashboardData d, String view, DashboardStat? platformStat) {
    if (view == 'platform') {
      final s = platformStat;
      return DashHero(
        icon: PhosphorIconsRegular.currencyCircleDollar,
        label: s == null ? 'nav.platformName'.tr : dashTr(s.key, s.label),
        figure: (s?.value ?? '—').replaceAll(' ', ' '),
        note: d.headline.isEmpty ? null : d.headline,
        actionLabel: 'nav.companies'.tr,
        onAction: () => controller.go('/platform/companies'),
      );
    }
    final b = d.banner;
    final waiting = b?.count ?? d.queue.length;
    final total = d.queueTotalText;
    return DashHero(
      icon: waiting > 0
          ? PhosphorIconsRegular.bellRinging
          : PhosphorIconsRegular.checkCircle,
      label: waiting == 0
          ? 'dashboard.hero.clear'.tr
          : view == 'admin'
          ? 'dashboard.stalled'.tr
          : 'dashboard.hero.waiting'.tr,
      figure: '$waiting',
      note: waiting > 0 && total != null && total.isNotEmpty ? total : null,
      actionLabel: 'dashboard.hero.review'.tr,
      onAction: d.queue.isEmpty ? null : controller.showQueue,
      // The full sentence stays for screen readers.
      semanticLabel: b == null
          ? null
          : [
              dashTr(b.key, b.title, b.params),
              dashTr(b.bodyKey, b.body),
            ].where((s) => s.isNotEmpty).join(' '),
    );
  }

  /// Round shortcuts into this role's own pages, as its navigation lists
  /// them; creating a voucher is the tab bar's raised +.
  Widget _quickActions(String role, int unread) {
    const skip = {'/dashboard', '/vouchers/new', '/notifications', '/profile'};
    final items = <(IconData, String, String)>[
      for (final i in navFor(role))
        if (!skip.contains(i.href)) (i.icon, i.short ?? i.label, i.href),
    ];
    if (role == 'employee') {
      items.add((PhosphorIconsRegular.chartLine, 'nav.reports', '/reports'));
    }
    final extras = <(IconData, String, String)>[
      (PhosphorIconsRegular.bell, 'dashboard.quick.alerts', '/notifications'),
      (PhosphorIconsRegular.user, 'dashboard.quick.me', '/profile'),
    ];
    for (final e in extras) {
      if (items.length >= 4) break;
      items.add(e);
    }
    final shown = items.take(4).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (icon, label, href) in shown)
          Expanded(
            child: DashQuickAction(
              icon: icon,
              label: label.tr,
              badge: href == '/notifications' ? unread : 0,
              onTap: () => controller.go(href),
            ),
          ),
      ],
    );
  }

  Widget _figures(
    DashboardData d,
    List<DashboardStat> stats,
    bool isPlatform,
    double width,
  ) {
    final count = stats.length;
    final cols = width < 700
        ? 2
        : (count % 4 == 0 && width >= 900)
        ? 4
        : 3;
    final tiles = <Widget>[];
    for (final s in stats) {
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
      // Only a trend or a note of a few words earns a line.
      final note = s.trend != null
          ? '${s.up == true ? '↑' : '↓'} ${s.trend}'
          : (sub.isNotEmpty && sub.trim().split(RegExp(r'\s+')).length <= 3)
          ? sub
          : null;
      tiles.add(
        DashStatTile(
          label: dashTr(s.key, s.label, s.params),
          // Unbreakable, so a long figure scales rather than wraps.
          value: s.value.replaceAll(' ', ' '),
          note: note,
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
    final bulk = view == 'approver' && d.queue.length > 1;
    return DashPanel(
      title: dashTr('dash.queue.$view', 'dashboard.needsYourAction'.tr),
      count: d.queue.length,
      trailing: bulk
          ? DashLink(
              label: 'nav.approvals'.tr,
              onTap: () => Get.find<ShellController>().go('/approvals'),
            )
          : null,
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

/// The shape of the home, so the page does not jump when data arrives.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    Widget block(double w, double h, double r) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: w,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: t.surface3,
          borderRadius: BorderRadius.circular(r),
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
              block(.3, 14, VfSize.radiusS),
              const SizedBox(height: 8),
              block(.5, 28, VfSize.radiusS),
              const SizedBox(height: 18),
              block(1, 150, 24),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: t.surface3,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        const VouchFlowLoadingState(rows: 2, rowHeight: 110),
      ],
    );
  }
}

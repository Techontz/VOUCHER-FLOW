import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/admin_models.dart';
import '../../data/services/admin_repository.dart';
import '../../data/services/session_service.dart';
import '../../widgets/common.dart' show Fmt, showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import 'admin_widgets.dart';

/// Subscription: a hero card with the plan, its status, renewal (or trial
/// end) and seats; usage against the plan's limits with auto-renew; billing
/// history with Pay now; and changing plan.
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key, this.repository});

  final AdminRepository? repository;

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  late final AdminRepository _repo = widget.repository ?? AdminRepository.to;
  SessionService? get _session =>
      Get.isRegistered<SessionService>() ? Get.find<SessionService>() : null;

  BillingState? _state;
  List<Invoice> _invoices = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    _repo.invoices().then(
      (v) {
        if (mounted) setState(() => _invoices = v);
      },
      onError: (_) {
        if (mounted) setState(() => _invoices = const []);
      },
    );
    try {
      final s = await _repo.billing();
      if (mounted) setState(() => _state = s);
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorText(e));
    }
  }

  Future<void> _refreshSession() async {
    try {
      await _session?.refresh();
    } catch (_) {}
  }

  Future<void> _toggleAutoRenew(bool value) async {
    try {
      await _repo.setAutoRenew(value);
      showToast(
        value ? 'admin.autoRenewOn'.tr : 'admin.autoRenewOff'.tr,
        kind: value ? ToastKind.ok : ToastKind.warn,
      );
      await _refreshSession();
      _load();
    } catch (e) {
      adminReport(e, 'admin.somethingWrong'.tr);
    }
  }

  String _metricLabel(UsageMetric m, int i) => [
    'admin.usageUsers',
    'admin.usageVouchers',
    'admin.usageDepartments',
    'admin.usageStorage',
  ][i].tr;

  String _statusLabel(String status) => switch (status) {
    'trial' => 'admin.coTrial'.tr,
    'active' => 'admin.coActive'.tr,
    'suspended' => 'admin.coSuspended'.tr,
    'expired' => 'admin.coExpired'.tr,
    _ => status,
  };

  Future<void> _openPlan() async {
    final s = _state!;
    int? selected = s.plan?.id;
    var cycle = 'monthly';
    var busy = false;
    Invoice? toPay;
    await showAdminSheet<void>(
      context,
      (ctx, setSheet) => VouchFlowDialog(
        icon: PhosphorIconsRegular.crownSimple,
        tone: VfTone.primary,
        title: 'admin.changePlan'.tr,
        actions: [
          VouchFlowButton(
            label: 'admin.cancel'.tr,
            variant: VfButtonVariant.secondary,
            onPressed: busy ? null : () => Navigator.of(ctx).pop(),
          ),
          VouchFlowButton(
            label: 'admin.confirm'.tr,
            loading: busy,
            onPressed: busy || selected == null
                ? null
                : () async {
                    setSheet(() => busy = true);
                    try {
                      final (message, invoice) = await _repo.subscribe(
                        selected!,
                        cycle,
                      );
                      showToast('admin.planChanged'.tr, body: message);
                      toPay = invoice;
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      await _refreshSession();
                      _load();
                    } catch (e) {
                      adminReport(e, 'admin.couldNotChangePlan'.tr);
                      if (ctx.mounted) setSheet(() => busy = false);
                    }
                  },
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final plan in s.availablePlans) ...[
              _PlanOption(
                plan: plan,
                selected: selected == plan.id,
                onTap: () => setSheet(() => selected = plan.id),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            Text(
              'admin.billingCycle'.tr,
              style: VfType.label.copyWith(
                color: ctx.vf.text2,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final c in const ['monthly', 'annual']) ...[
                  if (c == 'annual') const SizedBox(width: 8),
                  VouchFlowFilterChip(
                    label: c == 'annual'
                        ? 'admin.annual'.tr
                        : 'admin.monthly'.tr,
                    selected: cycle == c,
                    onTap: () => setSheet(() => cycle = c),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'admin.annualHint'.tr,
              style: VfType.meta.copyWith(color: ctx.vf.muted),
            ),
          ],
        ),
      ),
    );
    if (toPay != null && mounted) await _openPay(toPay!);
  }

  Future<void> _openPay(Invoice invoice) async {
    var method = 'mobile_money';
    final reference = TextEditingController();
    var busy = false;
    await showAdminSheet<void>(context, (ctx, setSheet) {
      final t = ctx.vf;
      final needsRef = method != 'bank_transfer';
      return VouchFlowDialog(
        icon: PhosphorIconsRegular.creditCard,
        tone: VfTone.primary,
        title: 'admin.payNow'.tr,
        actions: [
          VouchFlowButton(
            label: 'admin.cancel'.tr,
            variant: VfButtonVariant.secondary,
            onPressed: busy ? null : () => Navigator.of(ctx).pop(),
          ),
          VouchFlowButton(
            label: '${'admin.payNow'.tr} ${invoice.amountText}',
            loading: busy,
            onPressed: busy || (needsRef && reference.text.isEmpty)
                ? null
                : () async {
                    setSheet(() => busy = true);
                    try {
                      final paid = await _repo.pay(
                        invoice.id,
                        method,
                        needsRef ? reference.text : null,
                      );
                      showToast(
                        'admin.paymentSuccessful'.tr,
                        body: fill('admin.receiptLine'.tr, {
                          'amount': paid.amountText,
                          'ref': paid.providerRef,
                        }),
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      await _refreshSession();
                      _load();
                    } catch (e) {
                      adminReport(e, 'admin.paymentFailed'.tr);
                      if (ctx.mounted) setSheet(() => busy = false);
                    }
                  },
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${invoice.number} · ${invoice.description}',
              style: VfType.body.copyWith(color: t.text2),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                invoice.amountText,
                style: VfType.figure.copyWith(
                  color: t.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 14),
            VouchFlowDropdown<String>(
              label: 'admin.method'.tr,
              items: const ['mobile_money', 'card', 'bank_transfer'],
              value: method,
              itemLabel: (v) => switch (v) {
                'card' => 'admin.card'.tr,
                'bank_transfer' => 'admin.bankTransfer'.tr,
                _ => 'admin.mobileMoney'.tr,
              },
              onChanged: (v) => setSheet(() => method = v ?? method),
            ),
            const SizedBox(height: 12),
            if (needsRef)
              VouchFlowTextField(
                label: method == 'mobile_money'
                    ? 'admin.payMobilePrompt'.tr
                    : 'admin.cardNumber'.tr,
                controller: reference,
                required: true,
                placeholder: method == 'mobile_money'
                    ? '255712418226'
                    : '4111 1111 1111 1111',
                hint: 'admin.sandboxHint'.tr,
                keyboardType: method == 'mobile_money'
                    ? TextInputType.phone
                    : TextInputType.number,
                onChanged: (_) => setSheet(() {}),
              )
            else
              Text(
                'admin.bankTransferNote'.tr,
                style: VfType.small.copyWith(color: t.text2),
              ),
          ],
        ),
      );
    });
    reference.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final s = _state;
    final company = _session?.company.value;

    return AdminPageBody(
      route: '/subscription',
      title: 'admin.subscription'.tr,
      onRefresh: _load,
      children: [
        if (_error != null)
          VouchFlowErrorState(
            message: _error!,
            onRetry: _load,
            retryLabel: 'action.retry'.tr,
          )
        else if (s == null || company == null)
          const VouchFlowLoadingState(rows: 4, rowHeight: 120)
        else ...[
          if (s.isExpired) ...[
            VouchFlowAlert(
              tone: VfTone.bad,
              icon: PhosphorIconsRegular.warningCircle,
              title: 'admin.expired'.tr,
              message: 'admin.expiredBody'.tr,
            ),
            const SizedBox(height: 14),
          ],
          _hero(
            t,
            company.status,
            company.trialEndsAt,
            company.currentPeriodEnd,
            s,
          ),
          const SizedBox(height: 22),
          AdminSection(
            label: 'admin.usageThisPeriod'.tr,
            padding: const EdgeInsets.fromLTRB(16, 6, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminSwitch(
                  label: 'admin.autoRenew'.tr,
                  value: s.autoRenew,
                  onChanged: _toggleAutoRenew,
                ),
                Divider(height: 14, color: t.border),
                const SizedBox(height: 6),
                for (var i = 0; i < s.metrics.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _metric(
                      t,
                      _metricLabel(s.metrics[i], i),
                      s.metrics[i],
                    ),
                  ),
                  if (i < s.metrics.length - 1) const SizedBox(height: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          _history(t),
        ],
      ],
    );
  }

  /// The plan at a glance: name, status, renewal (or trial end) and seats,
  /// on the brand gradient, with Change plan.
  Widget _hero(
    VfTokens t,
    String status,
    DateTime? trialEndsAt,
    DateTime? periodEnd,
    BillingState s,
  ) {
    final trial = status == 'trial';
    final sb = s.subscription;
    final price = sb == null
        ? null
        : '${Fmt.money(sb.amount, sb.currency)} · ${sb.billingCycle == 'annual' ? 'admin.annual'.tr : 'admin.monthly'.tr}';
    final statusTone = switch (status) {
      'active' => VfTone.ok,
      'trial' => VfTone.warn,
      _ => VfTone.bad,
    };
    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: .78);

    Widget figure(String label, String value, String? sub) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: VfType.meta.copyWith(color: soft)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: VfType.figureS.copyWith(
                color: white,
                fontSize: 18,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (sub != null)
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VfType.meta.copyWith(color: soft),
            ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VfSize.radiusXl + 4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.palette.hoverDark, t.palette.primaryLight],
        ),
        boxShadow: [
          BoxShadow(
            color: t.palette.primaryLight.withValues(alpha: .28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Icon(
              PhosphorIconsFill.crownSimple,
              size: 150,
              color: Colors.white.withValues(alpha: .08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(VfSize.radiusL),
                      ),
                      child: const Icon(
                        PhosphorIconsFill.crownSimple,
                        size: 20,
                        color: white,
                      ),
                    ),
                    const Spacer(),
                    _HeroPill(
                      _statusLabel(status).capitalizeFirst ?? '',
                      tone: statusTone,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  s.plan?.name ?? 'admin.noPlan'.tr,
                  style: VfType.pageTitle.copyWith(color: white, fontSize: 26),
                ),
                if (price != null) ...[
                  const SizedBox(height: 2),
                  Text(price, style: VfType.small.copyWith(color: soft)),
                ],
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    figure(
                      trial ? 'admin.trialEnds'.tr : 'admin.renewsOn'.tr,
                      Fmt.date(trial ? trialEndsAt : periodEnd),
                      s.daysRemaining == null
                          ? null
                          : fill('admin.daysCount'.tr, {
                              'count': s.daysRemaining,
                            }),
                    ),
                    const SizedBox(width: 14),
                    figure(
                      'admin.seats'.tr,
                      '${s.users.used} / ${s.users.unlimited ? '∞' : s.users.limit}',
                      null,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: white,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: _openPlan,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 11,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIconsBold.arrowsLeftRight,
                              size: 16,
                              color: t.palette.hoverDark,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'admin.changePlan'.tr,
                              style: VfType.bodyStrong.copyWith(
                                color: t.palette.hoverDark,
                                fontSize: 14.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(VfTokens t, String label, UsageMetric m) {
    final unit = m.unit.isEmpty ? '' : ' ${m.unit}';
    final of = m.unlimited
        ? 'admin.unlimited'.tr
        : '${Fmt.plain(m.limit!.toDouble())}$unit';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: VfType.bodyStrong.copyWith(
                  color: t.text,
                  fontSize: 14.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${Fmt.plain(m.used.toDouble())}$unit ${'admin.of'.tr} $of',
                textAlign: TextAlign.right,
                style: VfType.small.copyWith(
                  color: m.exceeded ? t.dangerStrong : t.text2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AdminMeter(percent: m.percent ?? 4, exceeded: m.exceeded),
      ],
    );
  }

  Widget _history(VfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Text(
                'admin.billingHistory'.tr,
                style: VfType.label.copyWith(
                  color: t.muted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              AdminCount(_invoices.length),
            ],
          ),
        ),
        if (_invoices.isEmpty)
          VouchFlowCard(
            radius: VfSize.radiusXl,
            child: VouchFlowEmptyState(
              icon: PhosphorIconsRegular.receipt,
              title: 'admin.noInvoices'.tr,
            ),
          ),
        for (final inv in _invoices) _invoice(t, inv),
      ],
    );
  }

  Widget _invoice(VfTokens t, Invoice inv) {
    final (label, tone) = switch (inv.status) {
      'paid' => ('admin.invPaid'.tr, VfTone.ok),
      'pending' => ('admin.invPending'.tr, VfTone.warn),
      'failed' => ('admin.invFailed'.tr, VfTone.bad),
      _ => (inv.status, VfTone.neutral),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: VouchFlowCard(
        radius: VfSize.radiusXl,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AdminIconTile(
                  PhosphorIconsRegular.receipt,
                  tone: tone == VfTone.neutral ? VfTone.primary : tone,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inv.number,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VfType.bodyStrong.copyWith(
                          color: t.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        [
                          Fmt.date(inv.paidAt ?? inv.issuedAt),
                          if (inv.methodLabel.isNotEmpty &&
                              inv.methodLabel != '—')
                            inv.methodLabel,
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
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      inv.amountText,
                      style: VfType.bodyStrong.copyWith(
                        color: t.text,
                        fontSize: 14,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 3),
                    AdminBadge(label, tone: tone),
                  ],
                ),
              ],
            ),
            if (inv.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                inv.description,
                style: VfType.small.copyWith(color: t.text2),
              ),
            ],
            if (inv.failureReason != null) ...[
              const SizedBox(height: 6),
              Text(
                inv.failureReason!,
                style: VfType.small.copyWith(color: t.dangerStrong),
              ),
            ],
            if (inv.payable) ...[
              const SizedBox(height: 10),
              VouchFlowButton(
                label: 'admin.payNow'.tr,
                icon: PhosphorIconsRegular.creditCard,
                compact: true,
                expand: true,
                onPressed: () => _openPay(inv),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A frosted status pill on the hero card.
class _HeroPill extends StatelessWidget {
  const _HeroPill(this.label, {required this.tone});
  final String label;
  final VfTone tone;

  @override
  Widget build(BuildContext context) {
    final dot = switch (tone) {
      VfTone.ok => const Color(0xFF4ADE80),
      VfTone.warn => const Color(0xFFFBBF24),
      _ => const Color(0xFFF87171),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: VfType.meta.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final BillingPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    String n(int? v) => v == null ? 'admin.unlimitedCap'.tr : '$v';
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? t.primarySoft : t.surface2,
          borderRadius: BorderRadius.circular(VfSize.radiusXl),
          border: Border.all(
            color: selected ? t.primary : Colors.transparent,
            width: 1.6,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(VfSize.radiusXl),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          plan.name,
                          style: VfType.cardTitle.copyWith(color: t.text),
                        ),
                      ),
                      Icon(
                        selected
                            ? PhosphorIconsFill.checkCircle
                            : PhosphorIconsRegular.circle,
                        size: 24,
                        color: selected ? t.primary : t.faint,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: plan.price > 0
                              ? Fmt.money(plan.price, plan.currency)
                              : 'admin.customPrice'.tr,
                        ),
                        if (plan.price > 0)
                          TextSpan(
                            text: ' ${'admin.perMonthShort'.tr}',
                            style: VfType.small.copyWith(color: t.muted),
                          ),
                      ],
                    ),
                    style: VfType.figureS.copyWith(
                      color: selected ? t.primaryText : t.text,
                      fontSize: 19,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fill('admin.planLimits'.tr, {
                      'users': n(plan.maxUsers),
                      'vouchers': n(plan.maxVouchersPerMonth),
                      'levels': n(plan.maxApprovalLevels),
                    }),
                    style: VfType.meta.copyWith(color: t.text2, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

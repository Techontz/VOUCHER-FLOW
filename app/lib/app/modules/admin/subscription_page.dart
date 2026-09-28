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

/// Subscription — the web's page: the plan, its renewal or trial end, seats,
/// usage against the plan's limits with auto-renew, billing history with
/// Pay now, and changing plan.
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
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            VouchFlowDropdown<String>(
              label: 'admin.billingCycle'.tr,
              hint: 'admin.annualHint'.tr,
              items: const ['monthly', 'annual'],
              value: cycle,
              itemLabel: (v) =>
                  v == 'annual' ? 'admin.annual'.tr : 'admin.monthly'.tr,
              onChanged: (v) => setSheet(() => cycle = v ?? 'monthly'),
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

    String? sub;
    if (s != null) {
      final sb = s.subscription;
      sub = sb != null
          ? '${s.plan?.name ?? ''} · ${sb.billingCycle == 'annual' ? 'admin.annual'.tr : 'admin.monthly'.tr} · ${Fmt.money(sb.amount, sb.currency)}'
          : s.plan?.name ?? 'admin.noPlan'.tr;
    }

    return AdminPageBody(
      route: '/subscription',
      title: 'admin.subscription'.tr,
      subtitle: sub,
      onRefresh: _load,
      actions: s == null
          ? null
          : [
              VouchFlowButton(
                label: 'admin.changePlan'.tr,
                icon: PhosphorIconsRegular.crownSimple,
                onPressed: _openPlan,
              ),
            ],
      children: [
        if (_error != null)
          VouchFlowErrorState(
            message: _error!,
            onRetry: _load,
            retryLabel: 'action.retry'.tr,
          )
        else if (s == null || company == null)
          const VouchFlowLoadingState(rows: 5, rowHeight: 100)
        else ...[
          if (s.isExpired) ...[
            VouchFlowAlert(
              tone: VfTone.bad,
              icon: PhosphorIconsRegular.warningCircle,
              title: 'admin.expired'.tr,
              message: 'admin.expiredBody'.tr,
            ),
            const SizedBox(height: 14),
          ] else if (company.status == 'trial') ...[
            VouchFlowAlert(
              tone: VfTone.warn,
              icon: PhosphorIconsRegular.clock,
              title: '${'admin.trialEnds'.tr} ${Fmt.date(company.trialEndsAt)}',
              message: fill('admin.daysRemaining'.tr, {
                'count': s.daysRemaining,
              }),
            ),
            const SizedBox(height: 14),
          ],
          _figures(
            company.status,
            company.trialEndsAt,
            company.currentPeriodEnd,
            s,
          ),
          const SizedBox(height: 14),
          VouchFlowCard(
            title: 'admin.usageThisPeriod'.tr,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminSwitch(
                  label: 'admin.autoRenew'.tr,
                  value: s.autoRenew,
                  onChanged: _toggleAutoRenew,
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < s.metrics.length; i++) ...[
                  _metric(t, _metricLabel(s.metrics[i], i), s.metrics[i]),
                  if (i < s.metrics.length - 1) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _history(t),
        ],
      ],
    );
  }

  Widget _figures(
    String status,
    DateTime? trialEndsAt,
    DateTime? periodEnd,
    BillingState s,
  ) {
    final trial = status == 'trial';
    final cards = [
      VouchFlowStatCard(
        label: 'admin.currentPlan'.tr,
        value: s.plan?.name ?? '—',
        sub: _statusLabel(status),
        tone: VfTone.neutral,
      ),
      VouchFlowStatCard(
        label: trial ? 'admin.trialEnds'.tr : 'admin.renewsOn'.tr,
        value: Fmt.date(trial ? trialEndsAt : periodEnd),
        sub: s.daysRemaining == null
            ? null
            : fill('admin.daysCount'.tr, {'count': s.daysRemaining}),
        tone: VfTone.neutral,
      ),
      VouchFlowStatCard(
        label: 'admin.seats'.tr,
        value: '${s.users.used} / ${s.users.unlimited ? '∞' : s.users.limit}',
        sub: s.users.unlimited
            ? fill('admin.seatsUsedUnlimited'.tr, {'used': s.users.used})
            : fill('admin.seatsUsedN'.tr, {
                'used': s.users.used,
                'limit': s.users.limit,
              }),
        tone: VfTone.neutral,
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 600) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: cards[i]),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              cards[i],
            ],
          ],
        );
      },
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
    return VouchFlowCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'admin.billingHistory'.tr,
                    style: VfType.sectionTitle.copyWith(
                      color: t.text,
                      fontSize: 17,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AdminCount(_invoices.length),
              ],
            ),
          ),
          if (_invoices.isEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.border)),
              ),
              child: VouchFlowEmptyState(
                icon: PhosphorIconsRegular.receipt,
                title: 'admin.noInvoices'.tr,
              ),
            ),
          for (final inv in _invoices)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.border)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              inv.number,
                              style: VfType.bodyStrong.copyWith(
                                color: t.text,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            Text(
                              inv.description,
                              style: VfType.small.copyWith(color: t.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        inv.amountText,
                        style: VfType.bodyStrong.copyWith(
                          color: t.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AdminLine(label: 'admin.method'.tr, value: inv.methodLabel),
                  AdminLine(
                    label: 'admin.date'.tr,
                    value: Fmt.date(inv.paidAt ?? inv.issuedAt),
                  ),
                  AdminLine(
                    label: 'admin.status'.tr,
                    value: '',
                    valueWidget: AdminBadge(
                      switch (inv.status) {
                        'paid' => 'admin.invPaid'.tr,
                        'pending' => 'admin.invPending'.tr,
                        'failed' => 'admin.invFailed'.tr,
                        _ => inv.status,
                      },
                      tone: switch (inv.status) {
                        'paid' => VfTone.ok,
                        'failed' => VfTone.bad,
                        'pending' => VfTone.warn,
                        _ => VfTone.neutral,
                      },
                    ),
                  ),
                  if (inv.failureReason != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      inv.failureReason!,
                      style: VfType.small.copyWith(color: t.dangerStrong),
                    ),
                  ],
                  if (inv.payable) ...[
                    const SizedBox(height: 10),
                    VouchFlowButton(
                      label: 'admin.payNow'.tr,
                      compact: true,
                      expand: true,
                      onPressed: () => _openPay(inv),
                    ),
                  ],
                ],
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
      child: Material(
        color: selected ? t.primarySoft : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          side: BorderSide(
            color: selected ? t.primary : t.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 10, 0),
                  child: Icon(
                    selected
                        ? PhosphorIconsFill.radioButton
                        : PhosphorIconsRegular.circle,
                    size: 22,
                    color: selected ? t.primary : t.muted,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '${plan.name} — ${plan.price > 0 ? Fmt.money(plan.price, plan.currency) : 'admin.customPrice'.tr}',
                              ),
                              if (plan.price > 0)
                                TextSpan(
                                  text: ' ${'admin.perMonthShort'.tr}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w400,
                                    color: t.muted,
                                  ),
                                ),
                            ],
                          ),
                          style: VfType.bodyStrong.copyWith(color: t.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fill('admin.planLimits'.tr, {
                            'users': n(plan.maxUsers),
                            'vouchers': n(plan.maxVouchersPerMonth),
                            'levels': n(plan.maxApprovalLevels),
                          }),
                          style: VfType.small.copyWith(color: t.text2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

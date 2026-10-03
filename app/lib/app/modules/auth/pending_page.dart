import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import '../admin/subscription_page.dart';

/// What a self-registered company sees until the platform approves it: the
/// company, the plan it chose, a way to pay, and a status check. Nothing
/// else in the product is open to it yet (the API refuses with
/// `company_pending`).
class PendingApprovalPage extends StatefulWidget {
  const PendingApprovalPage({super.key});

  @override
  State<PendingApprovalPage> createState() => _PendingApprovalPageState();
}

class _PendingApprovalPageState extends State<PendingApprovalPage> {
  final _session = Get.find<SessionService>();
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      await _session.refresh();
      if (_session.company.value?.isPending == false) {
        Get.offAllNamed(Routes.shell);
        return;
      }
      showToast('pending.stillWaiting'.tr, kind: ToastKind.warn);
    } catch (_) {
      showToast('state.offline'.tr, kind: ToastKind.bad);
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _openBilling() async {
    await Get.to(
      () => VouchFlowPushedScaffold(
        title: 'pending.plan'.tr,
        body: const SubscriptionPage(),
      ),
    );
  }

  Future<void> _signOut() async {
    await _session.signOut();
    Get.offAllNamed(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: t.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          bottom: false,
          child: Obx(() {
            final company = _session.company.value;
            final plan = company?.plan;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                VfSize.pagePad,
                12,
                VfSize.pagePad,
                24 + bottom,
              ),
              children: [
                Row(
                  children: [
                    const Spacer(),
                    VfBarButton(
                      icon: PhosphorIconsRegular.signOut,
                      tooltip: 'nav.signOut'.tr,
                      onPressed: _signOut,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Center(child: _Badge()),
                const SizedBox(height: 28),
                Text(
                  'pending.title'.tr,
                  textAlign: TextAlign.center,
                  style: VfType.pageTitle.copyWith(
                    fontSize: 28,
                    letterSpacing: -.7,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 8),
                if (company != null)
                  Text(
                    company.name,
                    textAlign: TextAlign.center,
                    style: VfType.bodyStrong.copyWith(color: t.text2),
                  ),
                const SizedBox(height: 10),
                Text(
                  'pending.body'.tr,
                  textAlign: TextAlign.center,
                  style: VfType.body.copyWith(color: t.muted),
                ),
                const SizedBox(height: 28),
                if (plan != null) _PlanCard(plan: plan, onTap: _openBilling),
                const SizedBox(height: 16),
                _Steps(paid: company?.currentPeriodEnd != null),
                const SizedBox(height: 28),
                VouchFlowButton(
                  label: 'pending.payNow'.tr,
                  icon: PhosphorIconsRegular.creditCard,
                  height: 54,
                  expand: true,
                  onPressed: _openBilling,
                ),
                const SizedBox(height: 10),
                VouchFlowButton(
                  label: 'pending.check'.tr,
                  icon: PhosphorIconsRegular.arrowClockwise,
                  variant: VfButtonVariant.secondary,
                  height: 54,
                  expand: true,
                  loading: _checking,
                  onPressed: _check,
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// An hourglass in a soft glowing circle.
class _Badge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t.warningSoft,
      ),
      alignment: Alignment.center,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEA580C).withValues(alpha: .4),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(
          PhosphorIconsFill.hourglassMedium,
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onTap});
  final Plan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowCard(
      radius: VfSize.radiusXl,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: t.primarySoftStrong,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              PhosphorIconsRegular.crownSimple,
              color: t.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'pending.plan'.tr,
                  style: VfType.meta.copyWith(color: t.muted),
                ),
                Text(
                  plan.label,
                  style: VfType.bodyStrong.copyWith(color: t.text),
                ),
              ],
            ),
          ),
          Text(
            plan.price <= 0
                ? 'pending.free'.tr
                : '${plan.currency} ${_money(plan.price)}',
            style: VfType.bodyStrong.copyWith(color: t.text),
          ),
          const SizedBox(width: 6),
          Icon(PhosphorIconsRegular.caretRight, size: 16, color: t.faint),
        ],
      ),
    );
  }

  static String _money(double v) {
    final whole = v.round().toString();
    return whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }
}

/// Registered → paid → approved, the way in.
class _Steps extends StatelessWidget {
  const _Steps({required this.paid});
  final bool paid;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    Widget step(String label, bool done, bool current) {
      final colour = done
          ? t.successStrong
          : current
          ? t.primary
          : t.faint;
      return Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? t.successStrong : Colors.transparent,
              border: Border.all(color: colour, width: 2),
            ),
            child: done
                ? const Icon(
                    PhosphorIconsBold.check,
                    size: 14,
                    color: Colors.white,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: VfType.body.copyWith(
              color: done || current ? t.text : t.muted,
              fontWeight: current ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      );
    }

    return VouchFlowCard(
      radius: VfSize.radiusXl,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          step('pending.step.registered'.tr, true, false),
          const SizedBox(height: 14),
          step('pending.step.paid'.tr, paid, !paid),
          const SizedBox(height: 14),
          step('pending.step.approved'.tr, false, paid),
        ],
      ),
    );
  }
}

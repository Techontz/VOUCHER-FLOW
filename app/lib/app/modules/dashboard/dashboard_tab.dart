import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../shell/shell_page.dart';
import '../../widgets/common.dart';
import '../../widgets/design.dart';
import '../vouchers/voucher_card.dart';

class DashboardController extends GetxController {
  final repo = Get.find<VoucherRepository>();
  final session = Get.find<SessionService>();

  final data = Rxn<DashboardData>();
  final loading = true.obs;
  final error = RxnString();

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
}

class DashboardTab extends GetView<DashboardController> {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = Get.find<SessionService>();

    return Obx(() {
      if (controller.loading.value && controller.data.value == null) {
        return const SkeletonList(count: 3, header: true);
      }
      if (controller.error.value != null && controller.data.value == null) {
        return ErrorState(
          message: controller.error.value!,
          onRetry: controller.load,
        );
      }

      final d = controller.data.value!;
      final company = session.company.value;
      final me = session.me;
      final queueTitle = me.isCashier
          ? 'pay.queue'.tr
          : me.isEmployee
          ? 'queue.title'.tr
          : me.isAdmin
          ? 'queue.stalled'.tr
          : 'approvals.title'.tr;

      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            _CompanyRow(
              name: company?.name ?? 'app.name'.tr,
              initials: me.initials,
            ),
            const SizedBox(height: 18),
            Text(
              DateFormat('EEEE, d MMMM').format(DateTime.now()),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              '${_greeting()}, ${me.name.split(' ').first}',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),

            if (company != null && !company.isUsable) ...[
              NoticeBanner(
                icon: Icons.warning_amber_rounded,
                title: 'state.expired'.tr,
                body: 'state.expiredBody'.tr,
                tone: VfTone.bad,
              ),
              const SizedBox(height: 12),
            ],
            if (company != null &&
                company.isUsable &&
                company.status == 'trial') ...[
              NoticeBanner(
                icon: Icons.schedule,
                title: '${company.plan?.name ?? ''} trial',
                body:
                    '${company.daysRemaining ?? 0} days remaining · ends ${Fmt.date(company.trialEndsAt)}',
              ),
              const SizedBox(height: 12),
            ],

            if (d.queue.isNotEmpty)
              _NeedsYou(
                eyebrow: queueTitle,
                headline: d.headline,
                total: d.queueTotalText,
                sub: d.sub,
                onReview: () async {
                  await Get.toNamed(
                    Routes.voucher,
                    arguments: d.queue.first.id,
                  );
                  controller.load();
                },
              )
            else
              SectionCard(
                child: Row(
                  children: [
                    IconTile(
                      icon: Icons.done_all_rounded,
                      tone: VfTone.ok,
                      size: 44,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            me.isCashier ? 'pay.nothing'.tr : 'queue.empty'.tr,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(d.sub, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            if (d.stats.isNotEmpty) _Stats(stats: d.stats),

            if (d.queue.isNotEmpty) ...[
              const SizedBox(height: 24),
              SectionLabel(
                queueTitle,
                trailing: d.queueTotalText.isEmpty
                    ? null
                    : Text(
                        d.queueTotalText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFeatures: VfTheme.tabular,
                        ),
                      ),
              ),
              ...d.queue.map(
                (v) => VoucherCard(voucher: v, onReturn: controller.load),
              ),
              const SizedBox(height: 4),
              Text(
                me.isAdmin ? 'queue.stalledNote'.tr : 'queue.note'.tr,
                style: theme.textTheme.bodySmall,
              ),
            ],

            if (d.recent.isNotEmpty) ...[
              const SizedBox(height: 24),
              SectionLabel(
                'home.recent'.tr,
                trailing: TextButton(
                  onPressed: () => Get.find<ShellController>().index.value = 1,
                  child: Text('home.seeAll'.tr),
                ),
              ),
              ...d.recent.take(5).map(
                (v) => _RecentRow(voucher: v, onReturn: controller.load),
              ),
            ],

            if (d.queue.isEmpty && me.canCreateVouchers) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => Get.toNamed(
                  Routes.createVoucher,
                )?.then((_) => controller.load()),
                icon: const Icon(Icons.add, size: 18),
                label: Text('voucher.create'.tr),
              ),
            ],
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Get.find<ShellController>().index.value = 1,
              child: Text(
                me.isCashier || me.isApprover
                    ? 'nav.vouchers'.tr
                    : 'voucher.trackMine'.tr,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _CompanyRow extends StatelessWidget {
  const _CompanyRow({required this.name, required this.initials});

  final String name, initials;

  @override
  Widget build(BuildContext context) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => RegExp('^[A-Za-z]').hasMatch(w));
    final mark = words.take(2).map((w) => w[0].toUpperCase()).join();
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: VfColors.accent500,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            mark,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: VfColors.onAccent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            final shell = Get.find<ShellController>();
            shell.index.value = shell.showsQueue ? 4 : 3;
          },
          child: InitialsAvatar(initials: initials, size: 34),
        ),
      ],
    );
  }
}

/// The one thing to do next: what is waiting, how much, and a way in.
class _NeedsYou extends StatelessWidget {
  const _NeedsYou({
    required this.eyebrow,
    required this.headline,
    required this.total,
    required this.sub,
    required this.onReview,
  });

  final String eyebrow, headline, total, sub;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = context.vfAccent;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: context.vfAccentTint,
        border: Border.all(color: brand.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(VfTheme.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pending_actions_outlined, size: 15, color: brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  eyebrow.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(color: brand),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(headline, style: theme.textTheme.titleLarge),
          if (total.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              total,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: VfTheme.tabular,
              ),
            ),
          ],
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(sub, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onReview,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('home.reviewNow'.tr),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.stats});

  final List<DashboardStat> stats;

  @override
  Widget build(BuildContext context) {
    // Up to four sit in one row, as on the design; any more wrap two a row.
    if (stats.length <= 4) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: StatTile(label: stats[i].label, value: stats[i].value),
              ),
            ],
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in stats)
              SizedBox(
                width: width,
                child: StatTile(label: s.label, value: s.value),
              ),
          ],
        );
      },
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.voucher, required this.onReturn});

  final Voucher voucher;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = voucher.requesterName ?? '';
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0])
        .join();
    return InkWell(
      onTap: () async {
        await Get.toNamed(Routes.voucher, arguments: voucher.id);
        onReturn();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            InitialsAvatar(initials: initials, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${voucher.number} · ${voucher.purpose}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    '${voucher.statusLabel} · ${voucher.amountText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Fmt.relative(voucher.submittedAt ?? voucher.createdAt),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Greets by the device's own clock — the server's runs on UTC, three hours
/// behind Tanzania, which made every afternoon read "Good morning".
String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'home.goodMorning'.tr;
  if (hour < 17) return 'home.goodAfternoon'.tr;
  return 'home.goodEvening'.tr;
}

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
                title: '${company.plan?.name ?? ''} trial',
                body:
                    '${company.daysRemaining ?? 0} days remaining · ends ${Fmt.date(company.trialEndsAt)}',
                colour: VfColors.warn,
              ),

            Text(
              '${d.greeting}, ${session.me.name.split(' ').first}'
                  .toUpperCase(),
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: 6),
            Text(d.headline, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(d.sub, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Get.find<ShellController>().index.value = 1,
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(
                  session.me.isCashier || session.me.isApprover
                      ? 'nav.vouchers'.tr
                      : 'voucher.trackMine'.tr,
                ),
              ),
            ),
            const SizedBox(height: 22),

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
                            label: s.label,
                            value: s.value,
                            sub: s.sub,
                            icon: s.icon,
                            trend: s.trend,
                            up: s.up,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),

            if (d.queue.isNotEmpty) ...[
              const SizedBox(height: 26),
              SectionHeader(title: 'approvals.title'.tr),
              ...d.queue.map(
                (v) => VoucherCard(voucher: v, onReturn: controller.load),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.only(left: 10),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: VfColors.accent500, width: 2),
                  ),
                ),
                child: Text(
                  'approvals.signOnly'.tr,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],

            if (d.recent.isNotEmpty) ...[
              const SizedBox(height: 26),
              SectionHeader(title: 'nav.vouchers'.tr),
              ...d.recent.map(
                (v) => VoucherCard(voucher: v, onReturn: controller.load),
              ),
            ],

            if (d.recent.isEmpty && d.queue.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: EmptyView(
                  title: session.me.isCashier
                      ? 'pay.nothing'.tr
                      : 'voucher.none'.tr,
                  body: session.me.isCashier
                      ? 'pay.nothingBody'.tr
                      : 'voucher.noneBody'.tr,
                  action: session.me.canCreateVouchers
                      ? FilledButton(
                          onPressed: () => Get.toNamed(
                            Routes.createVoucher,
                          )?.then((_) => controller.load()),
                          child: Text('voucher.create'.tr),
                        )
                      : null,
                ),
              ),
          ],
        ),
      );
    });
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

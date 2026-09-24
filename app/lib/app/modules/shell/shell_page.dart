import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../dashboard/dashboard_tab.dart';
import '../notifications/notifications_tab.dart';
import '../profile/profile_tab.dart';
import '../vouchers/voucher_list_tab.dart';

/// The five-slot tab shell from the design.
///
/// The middle tab follows the role: an approver gets Approvals, a cashier gets
/// the Payment queue, and an employee gets neither, because nothing is ever
/// routed to them.
class ShellController extends GetxController {
  final session = Get.find<SessionService>();
  final index = 0.obs;

  late final bool isCashier = session.me.isCashier;
  late final bool showsQueue =
      session.me.isApprover || session.me.isAdmin || isCashier;

  late final VoucherListController register = Get.put(
    VoucherListController(),
    tag: 'register',
  );
  late final VoucherListController? queue = showsQueue
      ? Get.put(VoucherListController(pendingOnly: true), tag: 'queue')
      : null;

  void refreshCurrent() {
    switch (index.value) {
      case 0:
        Get.find<DashboardController>().load();
      case 1:
        register.load();
      default:
        if (showsQueue && index.value == 2) queue?.load();
    }
  }
}

class ShellPage extends GetView<ShellController> {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Get.find<SessionService>();

    return Obx(() {
      final tabs = <Widget>[
        const DashboardTab(),
        VoucherListTab(controller: controller.register),
        if (controller.showsQueue)
          VoucherListTab(controller: controller.queue!),
        const NotificationsTab(),
        const ProfileTab(),
      ];

      final queueCount = controller.queue?.vouchers.length ?? 0;

      Widget counted(Widget icon, int count) => Badge(
        isLabelVisible: count > 0,
        backgroundColor: VfBadge.background(Theme.of(context).brightness),
        textColor: VfBadge.foreground(Theme.of(context).brightness),
        label: Text('$count'),
        child: icon,
      );

      final destinations = <NavigationDestination>[
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home_rounded),
          label: 'nav.home'.tr,
        ),
        NavigationDestination(
          icon: const Icon(Icons.receipt_long_outlined),
          selectedIcon: const Icon(Icons.receipt_long),
          label: 'nav.vouchers'.tr,
        ),
        if (controller.showsQueue)
          NavigationDestination(
            icon: counted(
              Icon(
                controller.isCashier
                    ? Icons.account_balance_wallet_outlined
                    : Icons.fact_check_outlined,
              ),
              queueCount,
            ),
            selectedIcon: counted(
              Icon(
                controller.isCashier
                    ? Icons.account_balance_wallet
                    : Icons.fact_check,
              ),
              queueCount,
            ),
            label: controller.isCashier
                ? 'nav.payments'.tr
                : 'nav.approvals'.tr,
          ),
        NavigationDestination(
          icon: counted(
            const Icon(Icons.notifications_none),
            session.unread.value,
          ),
          selectedIcon: counted(
            const Icon(Icons.notifications),
            session.unread.value,
          ),
          label: 'nav.alerts'.tr,
        ),
        NavigationDestination(
          icon: const Icon(Icons.account_circle_outlined),
          selectedIcon: const Icon(Icons.account_circle),
          label: 'nav.profile'.tr,
        ),
      ];

      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(index: controller.index.value, children: tabs),
        ),
        floatingActionButton:
            !session.me.canCreateVouchers || controller.index.value > 1
            ? null
            : FloatingActionButton.extended(
                onPressed: () => Get.toNamed(
                  Routes.createVoucher,
                )?.then((_) => controller.refreshCurrent()),
                icon: const Icon(Icons.add),
                label: Text('voucher.new'.tr),
              ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.vfLine)),
          ),
          child: NavigationBar(
            selectedIndex: controller.index.value,
            onDestinationSelected: (i) {
              controller.index.value = i;
              controller.refreshCurrent();
            },
            destinations: destinations,
          ),
        ),
      );
    });
  }
}

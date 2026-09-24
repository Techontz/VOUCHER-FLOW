import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';

class NotificationsController extends GetxController {
  final repo = Get.find<VoucherRepository>();
  final session = Get.find<SessionService>();

  final items = <AppNotificationItem>[].obs;
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
      items.value = await repo.notifications();
      await session.refreshUnread();
    } on ApiException catch (e) {
      error.value = e.message;
    } catch (_) {
      error.value = 'state.offline'.tr;
    } finally {
      loading.value = false;
    }
  }

  Future<void> markAll() async {
    try {
      final count = await repo.markAllNotificationsRead();
      showToast('alerts.markAll'.tr, body: '$count');
      await load();
    } catch (_) {
      showToast('state.error'.tr, kind: ToastKind.bad);
    }
  }

  Future<void> open(AppNotificationItem item) async {
    if (item.isUnread) {
      try {
        await repo.markNotificationRead(item.id);
      } catch (_) {}
    }
    if (item.entityType == 'Voucher' && item.entityId != null) {
      await Get.toNamed(Routes.voucher, arguments: item.entityId);
    }
    await load();
  }
}

class NotificationsTab extends GetView<NotificationsController> {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      if (controller.loading.value && controller.items.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.error.value != null && controller.items.isEmpty) {
        return ErrorView(
          message: controller.error.value!,
          onRetry: controller.load,
        );
      }
      if (controller.items.isEmpty) {
        return EmptyView(
          icon: Icons.notifications_none,
          title: 'alerts.empty'.tr,
        );
      }

      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
          itemCount: controller.items.length + 1,
          itemBuilder: (_, index) {
            if (index == 0) {
              final unread = controller.items.where((i) => i.isUnread).length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        unread > 0 ? '$unread unread' : 'alerts.empty'.tr,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (unread > 0)
                      TextButton(
                        onPressed: controller.markAll,
                        child: Text('alerts.markAll'.tr),
                      ),
                  ],
                ),
              );
            }

            final item = controller.items[index - 1];
            return InkWell(
              onTap: () => controller.open(item),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: item.isUnread
                      ? theme.colorScheme.primary.withValues(alpha: .08)
                      : Colors.transparent,
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.isUnread
                          ? Icons.circle_notifications_outlined
                          : Icons.notifications_none,
                      size: 22,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: item.isUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          if (item.body != null)
                            Text(item.body!, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      Fmt.relative(item.createdAt),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    });
  }
}

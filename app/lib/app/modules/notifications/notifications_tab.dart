import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import '../../widgets/design.dart';

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

  /// Groups by calendar day, newest first: Today, Yesterday, then dates.
  static String _group(DateTime? at) {
    if (at == null) return 'alerts.earlier'.tr;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'alerts.today'.tr;
    if (diff == 1) return 'alerts.yesterday'.tr;
    return Fmt.date(at);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = controller.items;
      final unread = items.where((i) => i.isUnread).length;

      Widget body;
      if (controller.loading.value && items.isEmpty) {
        body = const SkeletonList(count: 4);
      } else if (controller.error.value != null && items.isEmpty) {
        body = ErrorState(
          message: controller.error.value!,
          onRetry: controller.load,
        );
      } else if (items.isEmpty) {
        body = RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            children: [
              const SizedBox(height: 60),
              EmptyState(
                icon: Icons.notifications_none,
                title: 'alerts.empty'.tr,
                body: 'alerts.emptyBody'.tr,
              ),
            ],
          ),
        );
      } else {
        final rows = <Widget>[];
        String? last;
        for (final item in items) {
          final group = _group(item.createdAt);
          if (group != last) {
            rows.add(_GroupHeader(group));
            last = group;
          }
          rows.add(_AlertRow(item: item, onTap: () => controller.open(item)));
        }
        body = RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: rows,
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenTitle(
            title: 'nav.alerts'.tr,
            trailing: unread > 0
                ? TextButton(
                    onPressed: controller.markAll,
                    child: Text('alerts.markAllShort'.tr),
                  )
                : null,
          ),
          Expanded(child: body),
        ],
      );
    });
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.vfLine)),
    ),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.item, required this.onTap});

  final AppNotificationItem item;
  final VoidCallback onTap;

  /// The event's icon and tone, read from the notification's own words.
  static (IconData, VfTone) _event(AppNotificationItem item) {
    final text = '${item.title} ${item.body ?? ''}'.toLowerCase();
    bool has(List<String> words) => words.any(text.contains);
    if (has(['reject', 'kataa', 'katal'])) {
      return (Icons.cancel_outlined, VfTone.bad);
    }
    if (has(['change', 'returned', 'mabadiliko'])) {
      return (Icons.u_turn_left, VfTone.warn);
    }
    if (has(['paid', 'lipwa', 'payment', 'malipo'])) {
      return (Icons.account_balance_wallet_outlined, VfTone.ok);
    }
    if (has(['approved', 'idhinish'])) {
      return (Icons.check_circle_outline, VfTone.ok);
    }
    if (has(['signed', 'signature', 'saini', 'sahihi'])) {
      return (Icons.draw_outlined, VfTone.info);
    }
    if (has(['submit', 'tuma', 'awaiting', 'subiri'])) {
      return (Icons.send_outlined, VfTone.info);
    }
    return (Icons.notifications_none, VfTone.neutral);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, tone) = _event(item);
    final at = item.createdAt;

    return Material(
      color: item.isUnread
          ? VfColors.accent500.withValues(alpha: context.isDark ? .07 : .05)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.vfLine)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: icon, tone: tone, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: item.isUnread
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (item.body != null && item.body!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(item.body!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    at == null ? '' : DateFormat('HH:mm').format(at),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      fontFeatures: VfTheme.tabular,
                    ),
                  ),
                  if (item.isUnread) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      label: 'alerts.unread'.tr,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: context.vfAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

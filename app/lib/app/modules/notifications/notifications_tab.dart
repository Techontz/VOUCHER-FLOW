import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/dashboard_repository.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart';

/// The inbox: approvals, decisions and billing events, newest first, grouped
/// by day. Opening one marks it read and goes to its voucher.
class NotificationsController extends GetxController {
  final repo = DashboardRepository.to;
  final session = Get.find<SessionService>();

  final items = Rxn<List<AppNotificationItem>>();
  final unread = 0.obs;
  final error = RxnString();
  final markingAll = false.obs;

  Worker? _localeWorker;

  @override
  void onInit() {
    super.onInit();
    load();
    _localeWorker = ever(session.locale, (_) => load());
  }

  @override
  void onClose() {
    _localeWorker?.dispose();
    super.onClose();
  }

  Future<void> load() async {
    error.value = null;
    try {
      final page = await repo.notifications();
      items.value = page.items;
      unread.value = page.unreadCount;
    } on ApiException catch (e) {
      error.value = e.message;
    } catch (_) {
      error.value = 'state.offline'.tr;
    }
  }

  Future<void> markAll() async {
    markingAll.value = true;
    try {
      final count = await repo.markAllNotificationsRead();
      showToast(
        'dashboard.inbox.caughtUp'.tr,
        body: 'dashboard.inbox.markedRead'.trParams({'count': '$count'}),
      );
      await load();
      unawaited(session.refreshUnread());
    } on ApiException catch (e) {
      showToast(
        'dashboard.inbox.updateFailed'.tr,
        body: e.message,
        kind: ToastKind.bad,
      );
    } catch (_) {
      showToast(
        'dashboard.inbox.updateFailed'.tr,
        body: 'state.offline'.tr,
        kind: ToastKind.bad,
      );
    } finally {
      markingAll.value = false;
    }
  }

  Future<void> open(AppNotificationItem item) async {
    if (item.isUnread) {
      try {
        await repo.markNotificationRead(item.id);
        unawaited(session.refreshUnread());
      } catch (_) {
        // Non-blocking: the voucher still opens.
      }
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
    return Obx(() {
      final items = controller.items.value;
      final unread = controller.unread.value;
      final marking = controller.markingAll.value;

      if (items == null && controller.error.value != null) {
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
      if (items == null) {
        return const VouchFlowPageBody(
          children: [VouchFlowLoadingState(rows: 5, rowHeight: 72)],
        );
      }

      return LayoutBuilder(
        builder: (context, box) {
          final pad = box.maxWidth >= 700 ? 24.0 : VfSize.pagePad;
          return VouchFlowPageBody(
            onRefresh: controller.load,
            padding: EdgeInsets.fromLTRB(pad, 20, pad, 32),
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      VouchFlowPageHeader(
                        title: 'dashboard.inbox.title'.tr,
                        subtitle: unread > 0
                            ? 'dashboard.inbox.unread'.trParams({
                                'count': '$unread',
                              })
                            : 'dashboard.inbox.empty'.tr,
                        actions: unread > 0
                            ? [
                                VouchFlowButton(
                                  label: 'dashboard.inbox.markAllRead'.tr,
                                  icon: PhosphorIconsRegular.checks,
                                  variant: VfButtonVariant.secondary,
                                  loading: marking,
                                  onPressed: controller.markAll,
                                ),
                              ]
                            : null,
                      ),
                      const SizedBox(height: 20),
                      _Inbox(items: items, onOpen: controller.open),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    });
  }
}

class _Inbox extends StatelessWidget {
  const _Inbox({required this.items, required this.onOpen});

  final List<AppNotificationItem> items;
  final void Function(AppNotificationItem) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final groups = _groupByDay(items);

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        border: Border.all(color: t.border),
        boxShadow: t.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: items.isEmpty
          ? VouchFlowEmptyState(
              icon: PhosphorIconsRegular.bellSlash,
              title: 'dashboard.inbox.empty'.tr,
              body: 'dashboard.inbox.emptyBody'.tr,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var g = 0; g < groups.length; g++) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: t.surface2,
                      border: Border(
                        top: g == 0
                            ? BorderSide.none
                            : BorderSide(color: t.border),
                        bottom: BorderSide(color: t.border),
                      ),
                    ),
                    child: Text(
                      'dashboard.inbox.${groups[g].$1}'.tr.toUpperCase(),
                      style: VfType.eyebrow.copyWith(
                        color: t.muted,
                        fontSize: 12,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                  for (var i = 0; i < groups[g].$2.length; i++)
                    _Item(
                      item: groups[g].$2[i],
                      divider: i > 0,
                      onTap: () => onOpen(groups[g].$2[i]),
                    ),
                ],
              ],
            ),
    );
  }

  /// Today, yesterday, earlier — the web's `groupByDay`.
  static List<(String, List<AppNotificationItem>)> _groupByDay(
    List<AppNotificationItem> items,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final out = <String, List<AppNotificationItem>>{
      'today': [],
      'yesterday': [],
      'earlier': [],
    };
    for (final item in items) {
      final at = item.createdAt;
      final day = at == null ? null : DateTime(at.year, at.month, at.day);
      if (day == today) {
        out['today']!.add(item);
      } else if (day == yesterday) {
        out['yesterday']!.add(item);
      } else {
        out['earlier']!.add(item);
      }
    }
    return [
      for (final e in out.entries)
        if (e.value.isNotEmpty) (e.key, e.value),
    ];
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.item, required this.divider, required this.onTap});

  final AppNotificationItem item;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final unread = item.isUnread;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            border: divider ? Border(top: BorderSide(color: t.border)) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: unread ? t.primarySoft : t.surface3,
                  borderRadius: BorderRadius.circular(VfSize.radiusM),
                ),
                child: Icon(
                  phIcon(item.icon),
                  size: 17,
                  color: unread ? t.primaryText : t.text2,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: VfType.body.copyWith(
                        color: t.text,
                        fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    if (item.body != null && item.body!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.body!,
                        style: VfType.small.copyWith(
                          color: t.text2,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      dashRelative(item.createdAt),
                      style: VfType.meta.copyWith(color: t.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Semantics(
                    label: 'dashboard.inbox.unreadMark'.tr,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: t.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

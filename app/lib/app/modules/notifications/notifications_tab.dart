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
import '../approvals/list_bits.dart';
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

      final groups = _groupByDay(items);
      return VouchFlowPageBody(
        onRefresh: controller.load,
        padding: const EdgeInsets.fromLTRB(
          VfSize.pagePad,
          16,
          VfSize.pagePad,
          32,
        ),
        children: [
          AppScreenTitle(
            title: 'dashboard.inbox.title'.tr,
            count: unread > 0 ? unread : null,
            trailing: [
              if (unread > 0)
                marking
                    ? const SizedBox(
                        width: 42,
                        height: 42,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : VfBarButton(
                        icon: PhosphorIconsRegular.checks,
                        tooltip: 'dashboard.inbox.markAllRead'.tr,
                        onPressed: controller.markAll,
                      ),
            ],
          ),
          const SizedBox(height: 18),
          if (items.isEmpty)
            VouchFlowCard(
              radius: VfSize.radiusXl,
              padding: EdgeInsets.zero,
              child: VouchFlowEmptyState(
                icon: PhosphorIconsRegular.bellSlash,
                title: 'dashboard.inbox.empty'.tr,
              ),
            )
          else
            for (var g = 0; g < groups.length; g++) ...[
              if (g > 0) const SizedBox(height: 20),
              AppListGroup(
                header: 'dashboard.inbox.${groups[g].$1}'.tr,
                indent: 70,
                children: [
                  for (final item in groups[g].$2)
                    _Item(item: item, onTap: () => controller.open(item)),
                ],
              ),
            ],
        ],
      );
    });
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
      final at = item.createdAt?.toLocal();
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

/// The tint for a notification's kind: good news green, a refusal red,
/// something to fix amber, billing blue, the rest in the accent.
(Color, Color) _tint(VfTokens t, String type) {
  bool has(List<String> words) => words.any(type.contains);
  if (has(['rejected', 'deleted', 'cancelled'])) {
    return (t.dangerStrong, t.dangerSoft);
  }
  if (has(['changes_requested', 'reminder', 'part_paid'])) {
    return (t.warningStrong, t.warningSoft);
  }
  if (has(['approved', 'paid', 'acknowledged', 'signed'])) {
    return (t.successStrong, t.successSoft);
  }
  if (has(['subscription', 'billing', 'company', 'plan'])) {
    return (t.infoStrong, t.infoSoft);
  }
  return (t.primaryText, t.primarySoft);
}

class _Item extends StatelessWidget {
  const _Item({required this.item, required this.onTap});

  final AppNotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final unread = item.isUnread;
    final (fg, bg) = unread ? _tint(t, item.type) : (t.text2, t.surface3);
    final body = item.body?.trim() ?? '';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconTile(
              icon: phIcon(item.icon),
              fg: fg,
              bg: bg,
              size: 42,
              circle: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: VfType.body.copyWith(
                            color: unread ? t.text : t.text2,
                            fontWeight: unread
                                ? FontWeight.w600
                                : FontWeight.w400,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          dashRelative(item.createdAt),
                          style: VfType.meta.copyWith(
                            color: unread ? t.primaryText : t.faint,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VfType.small.copyWith(color: t.muted),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          _Dot(color: t.primary),
                        ],
                      ],
                    ),
                  ] else if (unread)
                    Align(
                      alignment: Alignment.centerRight,
                      child: _Dot(color: t.primary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'dashboard.inbox.unreadMark'.tr,
    child: Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

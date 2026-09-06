import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';

/// The design's status chip.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.tag,
    this.dense = false,
  });

  final String label;
  final String tag;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: VfStatus.background(tag, brightness),
        border: Border.all(color: VfStatus.border(tag, brightness)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: dense ? 11 : 11.5,
          fontWeight: FontWeight.w500,
          color: VfStatus.foreground(tag, brightness),
        ),
      ),
    );
  }
}

/// A rule-topped statistic, as used on every dashboard in the design.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
  });

  final String label, value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.onSurface, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: theme.textTheme.headlineSmall),
          ),
          if (sub != null && sub!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(sub!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?trailing,
      ],
    ),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.body,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? body;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: VfColors.neutral500),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(
                body!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: VfColors.accent2600),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onRetry, child: Text('action.retry'.tr)),
          ],
        ],
      ),
    ),
  );
}

/// A short, non-blocking message. Colour follows the action's outcome.
void showToast(String title, {String? body, ToastKind kind = ToastKind.ok}) {
  final colour = switch (kind) {
    ToastKind.ok => VfColors.accent600,
    ToastKind.warn => VfColors.processYellow,
    ToastKind.bad => VfColors.accent2600,
  };

  Get.closeAllSnackbars();
  Get.rawSnackbar(
    titleText: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 15,
        color: Colors.white,
      ),
    ),
    messageText: body == null
        ? const SizedBox.shrink()
        : Text(
            body,
            style: const TextStyle(fontSize: 13.5, color: Colors.white70),
          ),
    backgroundColor: VfColors.neutral900,
    // A hairline in the toast's own accent, so the panel separates from the
    // dark ground it now usually sits on.
    borderColor: colour.withValues(alpha: .55),
    borderWidth: 1,
    margin: const EdgeInsets.all(12),
    borderRadius: 2,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    duration: const Duration(seconds: 3),
    snackPosition: SnackPosition.BOTTOM,
    icon: Icon(switch (kind) {
      ToastKind.ok => Icons.check_circle_outline,
      ToastKind.warn => Icons.schedule,
      ToastKind.bad => Icons.error_outline,
    }, color: colour),
  );
}

enum ToastKind { ok, warn, bad }

/// Shared formatting so dates and money read the same everywhere.
class Fmt {
  const Fmt._();

  static String money(double amount, [String currency = 'TZS']) {
    final pattern = amount % 1 == 0 ? '#,##0' : '#,##0.00';
    return '$currency ${NumberFormat(pattern, 'en_US').format(amount)}';
  }

  static String date(DateTime? value) =>
      value == null ? '—' : DateFormat('d MMM yyyy').format(value);

  static String dateTime(DateTime? value) =>
      value == null ? '—' : DateFormat('d MMM yyyy · HH:mm').format(value);

  static String relative(DateTime? value) {
    if (value == null) return '—';
    final diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return date(value);
  }
}

import 'dart:convert';
import 'dart:typed_data';

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
        borderRadius: BorderRadius.circular(VfTheme.rSm),
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

/// The v2 statistic card: iconed label, tabular value and an optional trend.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    this.trend,
    this.up,
  });

  final String label, value;
  final String? sub, trend, icon;
  final bool? up;

  static const _icons = <String, IconData>{
    'receipt': Icons.receipt_long_outlined,
    'hourglass': Icons.hourglass_bottom_outlined,
    'check': Icons.check_circle_outline,
    'coins': Icons.savings_outlined,
    'wallet': Icons.account_balance_wallet_outlined,
    'money': Icons.payments_outlined,
    'bank': Icons.account_balance_outlined,
    'signature': Icons.draw_outlined,
    'undo': Icons.undo_outlined,
    'seal': Icons.verified_outlined,
    'chart': Icons.show_chart,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rising = up ?? true;
    final trendColour = rising ? VfColors.ok : VfColors.bad;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: context.vfElev1,
        border: Border.all(color: context.vfLine),
        borderRadius: BorderRadius.circular(VfTheme.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: context.vfAccentTint,
                  border: Border.all(color: context.vfLine),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _icons[icon] ?? Icons.show_chart,
                  size: 15,
                  color: context.vfAccent,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: theme.textTheme.headlineSmall),
          ),
          if ((sub != null && sub!.isNotEmpty) || trend != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (trend != null && trend!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: trendColour.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(VfTheme.rSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          rising ? Icons.trending_up : Icons.trending_down,
                          size: 12,
                          color: trendColour,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          trend!,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: trendColour,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (sub != null && sub!.isNotEmpty)
                  Text(sub!, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Bank or cash — the two corporate voucher formats.
class KindChip extends StatelessWidget {
  const KindChip({super.key, required this.kind, this.dense = true});

  final String kind;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cash = kind == 'cash';
    final colour = cash ? VfColors.warn : context.vfAccent;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: 2),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(VfTheme.rSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            cash ? Icons.payments_outlined : Icons.account_balance_outlined,
            size: dense ? 12 : 14,
            color: colour,
          ),
          const SizedBox(width: 4),
          Text(
            (cash ? 'voucher.cashShort'.tr : 'voucher.bankShort'.tr)
                .toUpperCase(),
            style: TextStyle(
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: .4,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

/// The elevated surface almost every block sits on.
class VfPanel extends StatelessWidget {
  const VfPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.vfElev1,
      border: Border.all(color: context.vfLine),
      borderRadius: BorderRadius.circular(VfTheme.rLg),
    ),
    child: child,
  );
}

/// A large selectable option card — voucher format, payment method.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.selected,
    required this.onTap,
    required this.icon,
    required this.label,
    this.sub,
  });

  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(VfTheme.rLg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? context.vfAccentTint : context.vfElev1,
          border: Border.all(
            color: selected ? VfColors.accent400 : context.vfLine,
          ),
          borderRadius: BorderRadius.circular(VfTheme.rLg),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: context.vfElev2,
                border: Border.all(color: context.vfLine),
                borderRadius: BorderRadius.circular(VfTheme.rMd),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? context.vfAccent : context.vfMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: theme.textTheme.titleSmall),
                  if (sub != null) Text(sub!, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 20,
              color: selected ? context.vfAccent : context.vfMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft rule-led callout for scope, workflow and payment notes.
class VfNote extends StatelessWidget {
  const VfNote(this.text, {super.key, this.tone});

  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colour = tone ?? context.vfAccent;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .07),
        border: Border(left: BorderSide(color: colour, width: 2)),
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(VfTheme.rMd),
        ),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
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
            Icon(icon, size: 40, color: VfColors.lineStrong),
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
          const Icon(Icons.error_outline, size: 40, color: VfColors.bad),
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
    ToastKind.warn => VfColors.warn,
    ToastKind.bad => VfColors.bad,
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
    backgroundColor: VfColors.elev3,
    // A hairline in the toast's own accent, so the panel separates from the
    // dark ground it now usually sits on.
    borderColor: colour.withValues(alpha: .55),
    borderWidth: 1,
    margin: const EdgeInsets.all(12),
    borderRadius: VfTheme.rMd,
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

  /// The bare grouped figure, for a document column that already names its
  /// currency in the heading.
  static String plain(double amount) =>
      NumberFormat('#,##0', 'en_US').format(amount);

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

/// Decodes a signature data URL, returning null rather than throwing when the
/// payload is not base64 — a signature is decoration on a screen, never a
/// reason to fail a build.
Uint8List? decodeSignature(String? dataUrl) {
  if (dataUrl == null || dataUrl.isEmpty) return null;
  final comma = dataUrl.indexOf(',');
  final payload = comma == -1 ? dataUrl : dataUrl.substring(comma + 1);
  if (comma != -1 && !dataUrl.substring(0, comma).contains('base64')) {
    return null;
  }
  try {
    return base64Decode(payload);
  } on FormatException {
    return null;
  }
}

/// A collapsible secondary section.
///
/// Attachments, comments, the timeline and the audit trail matter, but they
/// are not the voucher — giving each a permanent slab pushes the document
/// itself off the screen. They live here instead: one line each until asked
/// for.
class Disclosure extends StatefulWidget {
  const Disclosure({
    super.key,
    required this.title,
    required this.child,
    this.count,
    this.icon,
    this.initiallyOpen = false,
  });

  final String title;
  final Widget child;
  final int? count;
  final IconData? icon;
  final bool initiallyOpen;

  @override
  State<Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<Disclosure> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.vfElev1,
        border: Border.all(color: context.vfLine),
        borderRadius: BorderRadius.circular(VfTheme.rLg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(VfTheme.rLg),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 17, color: context.vfMuted),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if ((widget.count ?? 0) > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: context.vfElev3,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${widget.count}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  Icon(
                    _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 20,
                    color: context.vfMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

/// The printed document, framed and scaled to whatever width it is given.
///
/// The sheet keeps its A4 geometry and is scaled as a whole, so what is on
/// screen is exactly what prints — it is never re-laid-out to fit a phone.
class DocumentFrame extends StatelessWidget {
  const DocumentFrame({super.key, required this.child, this.sheetWidth = 794});

  final Widget child;
  final double sheetWidth;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.vfElev2,
            border: Border.all(color: context.vfLine),
            borderRadius: BorderRadius.circular(VfTheme.rLg),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            // The sheet is scaled as a whole rather than reflowed, so the
            // printed geometry survives the phone.
            child: AspectRatio(
              aspectRatio: 794 / 1123,
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

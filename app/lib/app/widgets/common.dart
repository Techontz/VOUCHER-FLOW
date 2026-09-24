import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';

/// A compact statistic: the figure over a short muted label.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: context.vfElev1,
        border: Border.all(color: context.vfLine),
        borderRadius: BorderRadius.circular(VfTheme.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 18,
                fontFeatures: VfTheme.tabular,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
          ),
        ],
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

/// A short, non-blocking message. Colour follows the action's outcome.
void showToast(String title, {String? body, ToastKind kind = ToastKind.ok}) {
  final colour = switch (kind) {
    ToastKind.ok => VfColors.ok,
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

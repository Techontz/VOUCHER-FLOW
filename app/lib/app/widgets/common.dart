import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme.dart';
import 'vf/vf.dart';

/*
 * The shared widgets older screens are built from. Their constructors are
 * unchanged; underneath, each one now draws the web client's component
 * (widgets/vf) so every screen reads as the same product as the website.
 */

/// A status pill — the web's `.badge` in the voucher's `tag-*` tone.
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
  Widget build(BuildContext context) =>
      VouchFlowStatusBadge(label: label, tag: tag);
}

/// A statistic card — the web's `.vf-kpi`: label, big figure, an optional
/// trend and a quieter line, with a round tinted icon on the right.
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

  /// Short names older screens use, and the web's own `ph-*` names.
  static final _icons = <String, IconData>{
    'receipt': PhosphorIconsRegular.receipt,
    'hourglass': PhosphorIconsRegular.hourglass,
    'check': PhosphorIconsRegular.checkCircle,
    'coins': PhosphorIconsRegular.coins,
    'wallet': PhosphorIconsRegular.wallet,
    'money': PhosphorIconsRegular.money,
    'bank': PhosphorIconsRegular.bank,
    'signature': PhosphorIconsRegular.signature,
    'undo': PhosphorIconsRegular.arrowUUpLeft,
    'seal': PhosphorIconsRegular.sealCheck,
    'chart': PhosphorIconsRegular.chartLine,
    'ph-receipt': PhosphorIconsRegular.receipt,
    'ph-hourglass': PhosphorIconsRegular.hourglass,
    'ph-hourglass-medium': PhosphorIconsRegular.hourglassMedium,
    'ph-check-circle': PhosphorIconsRegular.checkCircle,
    'ph-seal-check': PhosphorIconsRegular.sealCheck,
    'ph-coins': PhosphorIconsRegular.coins,
    'ph-wallet': PhosphorIconsRegular.wallet,
    'ph-money': PhosphorIconsRegular.money,
    'ph-bank': PhosphorIconsRegular.bank,
    'ph-signature': PhosphorIconsRegular.signature,
    'ph-arrow-u-up-left': PhosphorIconsRegular.arrowUUpLeft,
    'ph-x-circle': PhosphorIconsRegular.xCircle,
    'ph-chart-line': PhosphorIconsRegular.chartLine,
    'ph-chart-bar': PhosphorIconsRegular.chartBar,
    'ph-users': PhosphorIconsRegular.users,
    'ph-buildings': PhosphorIconsRegular.buildings,
    'ph-clock': PhosphorIconsRegular.clock,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final rising = up ?? true;
    final trendColour = rising ? t.success : t.danger;
    final hasFoot = (sub != null && sub!.isNotEmpty) || (trend != null && trend!.isNotEmpty);

    Widget plate(double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: t.primarySoftStrong, shape: BoxShape.circle),
      child: Icon(_icons[icon] ?? PhosphorIconsRegular.chartBar, size: size * .5, color: t.primary),
    );

    Widget labelText() => Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: VfType.small.copyWith(color: t.text2, fontSize: 14, height: 1.3),
    );

    final figure = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(value, maxLines: 1, style: VfType.figure.copyWith(color: t.text, fontSize: 24)),
    );

    final foot = !hasFoot
        ? null
        : Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (trend != null && trend!.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      rising ? PhosphorIconsRegular.trendUp : PhosphorIconsRegular.trendDown,
                      size: 13,
                      color: trendColour,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trend!,
                      style: VfType.meta.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: trendColour),
                    ),
                  ],
                ),
              if (sub != null && sub!.isNotEmpty)
                Text(sub!, style: VfType.meta.copyWith(fontSize: 13, color: t.muted)),
            ],
          );

    return VouchFlowCard(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, box) {
          // In a narrow two-up grid the icon joins the label's line and the
          // figure takes the card's full width (the web's `data-long` card).
          if (box.maxWidth < 220) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: labelText()),
                    const SizedBox(width: 8),
                    plate(32),
                  ],
                ),
                const SizedBox(height: 6),
                figure,
                if (foot != null) ...[const SizedBox(height: 6), foot],
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    labelText(),
                    const SizedBox(height: 4),
                    figure,
                    if (foot != null) ...[const SizedBox(height: 6), foot],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              plate(44),
            ],
          );
        },
      ),
    );
  }
}

/// Bank or cash — the two corporate voucher formats (the web's `.vf-kind`).
class KindChip extends StatelessWidget {
  const KindChip({super.key, required this.kind, this.dense = true});

  final String kind;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final cash = kind == 'cash';
    return Container(
      height: dense ? 22 : 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(VfSize.radiusXs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            cash ? PhosphorIconsRegular.money : PhosphorIconsRegular.bank,
            size: dense ? 13 : 15,
            color: t.text,
          ),
          const SizedBox(width: 5),
          Text(
            cash ? 'voucher.cashShort'.tr : 'voucher.bankShort'.tr,
            style: VfType.meta.copyWith(
              fontSize: dense ? 12 : 13,
              fontWeight: FontWeight.w500,
              color: t.text,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The surface almost every block sits on — the web's `.vf-panel`.
class VfPanel extends StatelessWidget {
  const VfPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => VouchFlowCard(
    padding: padding ?? const EdgeInsets.all(VfSize.cardPad),
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
  Widget build(BuildContext context) => VouchFlowSelectCard(
    title: label,
    subtitle: sub,
    selected: selected,
    onTap: onTap,
    icon: icon,
  );
}

/// A quiet callout for scope, workflow and payment notes — the web's
/// `.vf-note`. A [tone] colour tints it (a warning, say).
class VfNote extends StatelessWidget {
  const VfNote(this.text, {super.key, this.tone});

  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final colour = tone;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: colour == null ? t.surface2 : Color.alphaBlend(colour.withValues(alpha: .10), t.surface),
        border: Border.all(color: colour == null ? t.border : colour.withValues(alpha: .30)),
        borderRadius: BorderRadius.circular(VfSize.radiusL),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(PhosphorIconsRegular.info, size: 17, color: colour ?? t.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: VfType.small.copyWith(fontSize: 14, color: t.text2, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

/// A section heading inside a page.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: VouchFlowSectionHeader(title: title, trailing: trailing),
  );
}

/// Nothing to show — the web's empty state: a soft round icon plate, a
/// title, a line and an optional action.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.body,
    this.icon = PhosphorIconsRegular.tray,
    this.action,
  });

  final String title;
  final String? body;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        VouchFlowEmptyState(title: title, body: body, icon: icon),
        if (action != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: action!,
          ),
      ],
    ),
  );
}

/// A failed load, with the server's wording and a retry.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(VfSize.pagePad),
      child: VouchFlowErrorState(
        message: message,
        onRetry: onRetry,
        retryLabel: 'action.retry'.tr,
      ),
    ),
  );
}

/// A short, non-blocking message in the web's toast look: a surface card with
/// a tone-coloured icon, a title and a line, rising above the tab bar.
void showToast(String title, {String? body, ToastKind kind = ToastKind.ok}) {
  final t = Get.isDarkMode
      ? VfTokens.dark(VfColors.palette)
      : VfTokens.light(VfColors.palette);
  final (IconData icon, Color colour) = switch (kind) {
    ToastKind.ok => (PhosphorIconsFill.checkCircle, t.successStrong),
    ToastKind.warn => (PhosphorIconsFill.info, t.warningStrong),
    ToastKind.bad => (PhosphorIconsFill.warningCircle, t.dangerStrong),
  };

  Get.closeAllSnackbars();
  Get.showSnackbar(
    GetSnackBar(
      titleText: Text(
        title,
        style: VfType.bodyStrong.copyWith(color: t.text, height: 1.35),
      ),
      messageText: body == null || body.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                body,
                style: VfType.small.copyWith(fontSize: 14, color: t.text2),
              ),
            ),
      icon: Icon(icon, size: 21, color: colour),
      shouldIconPulse: false,
      mainButton: IconButton(
        tooltip: 'action.close'.tr,
        onPressed: () => Get.closeCurrentSnackbar(),
        icon: Icon(PhosphorIconsRegular.x, size: 15, color: t.muted),
      ),
      backgroundColor: t.surface,
      borderColor: t.border,
      borderWidth: 1,
      borderRadius: VfSize.radiusL,
      boxShadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: t.isDark ? .5 : .12),
          blurRadius: 15,
          spreadRadius: -3,
          offset: const Offset(0, 10),
        ),
      ],
      maxWidth: 420,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      duration: const Duration(seconds: 3),
      snackPosition: SnackPosition.BOTTOM,
    ),
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

/// A collapsible secondary section — the web's `.vf-disclosure` panel.
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
    final t = context.vf;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: VouchFlowCard(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: _open,
              child: InkWell(
                onTap: () => setState(() => _open = !_open),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
                    child: Row(
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 18, color: t.text2),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            widget.title,
                            style: VfType.cardTitle.copyWith(color: t.text),
                          ),
                        ),
                        if ((widget.count ?? 0) > 0)
                          Container(
                            margin: const EdgeInsets.only(right: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                            decoration: BoxDecoration(
                              color: t.surface3,
                              borderRadius: BorderRadius.circular(VfSize.radiusPill),
                            ),
                            child: Text(
                              '${widget.count}',
                              style: VfType.meta.copyWith(color: t.text2, fontWeight: FontWeight.w600),
                            ),
                          ),
                        AnimatedRotation(
                          turns: _open ? .5 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: Icon(PhosphorIconsRegular.caretDown, size: 16, color: t.text2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: widget.child,
              ),
          ],
        ),
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
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(VfSize.radiusL),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VfSize.radiusXs),
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
  }
}

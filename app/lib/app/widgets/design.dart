/// The design system's shared building blocks: status badges, amounts,
/// section cards, sheets, and the loading, empty and error states.
///
/// Every screen composes these rather than styling its own, so a change to
/// the look is made once, here.
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../data/models/models.dart';

/// The five tones a status or a notice can carry. Colour never stands alone:
/// every use pairs it with an icon and a label.
enum VfTone { neutral, info, warn, ok, bad, brand }

extension VfToneColour on VfTone {
  Color colour(BuildContext context) => switch (this) {
    VfTone.neutral => context.vfInk2,
    VfTone.info => context.vfInfo,
    VfTone.warn => context.vfWarn,
    VfTone.ok => context.vfOk,
    VfTone.bad => context.vfBad,
    VfTone.brand => context.vfAccent,
  };

  Color soft(BuildContext context) => this == VfTone.neutral
      ? context.vfElev2
      : this == VfTone.brand
      ? context.vfAccentTint
      : colour(context).withValues(alpha: context.isDark ? .13 : .11);
}

/// How a voucher's status is drawn. Mapped from the API's own values — the
/// label shown is always the API's `status_label`.
class VoucherStatusStyle {
  const VoucherStatusStyle({
    required this.icon,
    required this.tone,
    this.bordered = false,
    this.struck = false,
  });

  final IconData icon;
  final VfTone tone;
  final bool bordered, struck;

  static VoucherStatusStyle of(Voucher v) {
    switch (v.status) {
      case 'draft':
        return const VoucherStatusStyle(
          icon: Icons.edit_outlined,
          tone: VfTone.neutral,
        );
      case 'changes_requested':
        return const VoucherStatusStyle(
          icon: Icons.u_turn_left,
          tone: VfTone.warn,
        );
      case 'approved':
        return const VoucherStatusStyle(
          icon: Icons.check_circle_outline,
          tone: VfTone.ok,
        );
      case 'paid':
        return const VoucherStatusStyle(icon: Icons.check_circle, tone: VfTone.ok);
      case 'rejected':
        return const VoucherStatusStyle(
          icon: Icons.cancel_outlined,
          tone: VfTone.bad,
        );
      case 'cancelled':
        return const VoucherStatusStyle(
          icon: Icons.block,
          tone: VfTone.neutral,
          bordered: true,
          struck: true,
        );
    }
    // In review: the step decides how it reads.
    switch (v.statusKey) {
      case 'signed':
        return const VoucherStatusStyle(
          icon: Icons.draw_outlined,
          tone: VfTone.info,
          bordered: true,
        );
      case 'awaiting_payment':
        return const VoucherStatusStyle(
          icon: Icons.check_circle_outline,
          tone: VfTone.ok,
        );
      case 'changes':
        return const VoucherStatusStyle(
          icon: Icons.u_turn_left,
          tone: VfTone.warn,
        );
    }
    return const VoucherStatusStyle(
      icon: Icons.hourglass_top_rounded,
      tone: VfTone.info,
    );
  }
}

/// A voucher's status: icon + label on a soft tone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.voucher, this.dense = false});

  final Voucher voucher;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final style = VoucherStatusStyle.of(voucher);
    return ToneBadge(
      label: voucher.statusLabel,
      icon: style.icon,
      tone: style.tone,
      bordered: style.bordered,
      struck: style.struck,
      dense: dense,
    );
  }
}

/// The badge shape itself, for anything that is not a voucher status.
class ToneBadge extends StatelessWidget {
  const ToneBadge({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.bordered = false,
    this.struck = false,
    this.dense = false,
  });

  final String label;
  final VfTone tone;
  final IconData? icon;
  final bool bordered, struck, dense;

  @override
  Widget build(BuildContext context) {
    final colour = tone.colour(context);
    final outlineOnly = struck;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 8, vertical: 3),
      decoration: BoxDecoration(
        color: outlineOnly ? Colors.transparent : tone.soft(context),
        border: bordered || outlineOnly
            ? Border.all(
                color: outlineOnly
                    ? context.vfLineStrong
                    : colour.withValues(alpha: .45),
              )
            : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 13, color: colour),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: VfTheme.fontFamily,
                fontSize: dense ? 11.5 : 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
                color: colour,
                decoration: struck ? TextDecoration.lineThrough : null,
                decorationColor: colour,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Voucher numbers and references, in a monospace face.
class Mono extends StatelessWidget {
  const Mono(this.text, {super.key, this.size = 12, this.colour});

  final String text;
  final double size;
  final Color? colour;

  static TextStyle style(BuildContext context, {double size = 12, Color? colour}) =>
      TextStyle(
        fontFamily: VfTheme.monoFamily,
        fontFamilyFallback: VfTheme.monoFallback,
        fontSize: size,
        height: 1.3,
        letterSpacing: .2,
        color: colour ?? context.vfMuted,
      );

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: style(context, size: size, colour: colour),
  );
}

/// An amount: a small muted currency code, then the figure in tabular digits.
class AmountText extends StatelessWidget {
  const AmountText({
    super.key,
    required this.amount,
    this.currency = 'TZS',
    this.size = 30,
    this.colour,
  });

  final double amount;
  final String currency;
  final double size;
  final Color? colour;

  static String figure(double amount) => NumberFormat(
    amount % 1 == 0 ? '#,##0' : '#,##0.00',
    'en_US',
  ).format(amount);

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$currency ',
              style: TextStyle(
                fontSize: (size * .42).clamp(10, 14).toDouble(),
                fontWeight: FontWeight.w500,
                color: context.vfMuted,
              ),
            ),
            TextSpan(
              text: figure(amount),
              style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w600,
                letterSpacing: -size * .01,
                color: colour ?? context.vfInk,
                fontFeatures: VfTheme.tabular,
              ),
            ),
          ],
        ),
        maxLines: 1,
        style: const TextStyle(fontFamily: VfTheme.fontFamily, height: 1.15),
      ),
    );
  }
}

/// A tab's large title, with an optional action at its right.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.displaySmall,
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A square, softly filled plate holding one icon.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.tone = VfTone.neutral,
    this.size = 40,
  });

  final IconData icon;
  final VfTone tone;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: tone == VfTone.neutral ? context.vfElev2 : tone.soft(context),
      border: Border.all(color: context.vfLine),
      borderRadius: BorderRadius.circular(size * .28),
    ),
    child: Icon(icon, size: size * .46, color: tone.colour(context)),
  );
}

/// A card on the surface step: radius 16 and a hairline, no shadow.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.colour,
    this.borderColour,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? colour, borderColour;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(VfTheme.rLg);
    return Material(
      color: colour ?? context.vfElev1,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: borderColour ?? context.vfLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Label-and-value rows separated by hairlines, as on the voucher summary.
class InfoRows extends StatelessWidget {
  const InfoRows({super.key, required this.rows});

  final List<(String, Widget)> rows;

  static Widget value(BuildContext context, String text) => Text(
    text,
    textAlign: TextAlign.right,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: context.vfInk,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: context.vfLine)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rows[i].$1,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.vfMuted,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: rows[i].$2,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A small caps-free section label above a block.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontSize: 16),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A tinted notice with an icon: offline, subscription, saved signature.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.tone = VfTone.warn,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final VfTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colour = tone.colour(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: context.isDark ? .09 : .08),
        border: Border.all(color: colour.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(VfTheme.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: colour),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: colour,
                  ),
                ),
                if (body != null && body!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      body!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.vfInk2,
                      ),
                    ),
                  ),
                if (action != null) ...[const SizedBox(height: 6), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Why a list is empty and the one useful next step.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.body,
    this.icon = Icons.inbox_outlined,
    this.tone = VfTone.neutral,
    this.action,
  });

  final String title;
  final String? body;
  final IconData icon;
  final VfTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTile(icon: icon, tone: tone, size: 52),
            const SizedBox(height: 18),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.vfMuted,
                ),
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

/// What failed, then the recovery action.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off_outlined,
    tone: VfTone.bad,
    title: 'state.error'.tr,
    body: message,
    action: onRetry == null
        ? null
        : FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 22),
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text('action.retry'.tr),
          ),
  );
}

/// A pulsing placeholder in the shape of the content that is coming.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: .55, end: 1).animate(_pulse),
    child: widget.child,
  );
}

/// One grey bar of a skeleton.
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({super.key, required this.width, this.height = 10});

  final double width, height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.vfElev3,
      borderRadius: BorderRadius.circular(6),
    ),
  );
}

/// The voucher-card skeleton list shown while a list first loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4, this.header = false});

  final int count;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          if (header) ...[
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: context.vfElev2,
                borderRadius: BorderRadius.circular(VfTheme.rMd),
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        SkeletonBar(width: 110),
                        Spacer(),
                        SkeletonBar(width: 40),
                      ],
                    ),
                    SizedBox(height: 12),
                    SkeletonBar(width: 220),
                    SizedBox(height: 12),
                    SkeletonBar(width: 120, height: 18),
                    SizedBox(height: 12),
                    SkeletonBar(width: 170),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A pill-shaped filter chip: selected reads as a filled ink pill.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? context.vfBg : context.vfInk2;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? context.vfInk : Colors.transparent,
            border: Border.all(
              color: selected ? context.vfInk : context.vfLineStrong,
            ),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A two-way segmented switch on the raised step, as in Bank / Cash.
class VfSegmented<T> extends StatelessWidget {
  const VfSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.compact = false,
  });

  final T value;
  final List<(T, String, IconData?)> options;
  final ValueChanged<T> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.vfElev2,
        border: Border.all(color: context.vfLine),
        borderRadius: BorderRadius.circular(VfTheme.rMd),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          for (final option in options)
            _wrap(
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(option.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: compact ? 32 : 40,
                  padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: option.$1 == value
                        ? context.vfElev3
                        : Colors.transparent,
                    border: option.$1 == value
                        ? Border.all(color: context.vfLineStrong)
                        : null,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (option.$3 != null) ...[
                        Icon(
                          option.$3,
                          size: 15,
                          color: option.$1 == value
                              ? context.vfInk
                              : context.vfMuted,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        option.$2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: option.$1 == value
                              ? context.vfInk
                              : context.vfMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _wrap(Widget child) => compact ? child : Expanded(child: child);
}

/// Bank or cash, as a small outlined tag.
class KindTag extends StatelessWidget {
  const KindTag({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final cash = kind == 'cash';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: context.vfElev2,
        border: Border.all(color: context.vfLine),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            cash ? Icons.payments_outlined : Icons.account_balance_outlined,
            size: 12,
            color: context.vfInk2,
          ),
          const SizedBox(width: 4),
          Text(
            cash ? 'voucher.cashShort'.tr : 'voucher.bankShort'.tr,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: context.vfInk2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A round initials avatar.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.initials, this.size = 32});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.vfElev3,
      border: Border.all(color: context.vfLineStrong),
      shape: BoxShape.circle,
    ),
    child: Text(
      initials.isEmpty ? '·' : initials,
      style: TextStyle(
        fontSize: size * .34,
        fontWeight: FontWeight.w600,
        color: context.vfInfo,
      ),
    ),
  );
}

/// Opens a bottom sheet on the overlay step, sized to its content and lifted
/// above the keyboard.
Future<T?> showVfSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: builder,
);

/// The body of every sheet: a title row, an optional line under it, then
/// the content, padded and scrollable above the keyboard.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? eyebrow;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null) ...[
                        eyebrow!,
                        const SizedBox(height: 4),
                      ],
                      Text(title, style: theme.textTheme.titleLarge),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.vfMuted,
                ),
              ),
            ],
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A field label with an optional required mark, placed above its input.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text.rich(
      TextSpan(
        text: text,
        children: [
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(color: context.vfAccent),
            ),
        ],
      ),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: context.vfInk2,
      ),
    ),
  );
}

/// The sticky action area at the bottom of a screen: a hairline above and
/// the buttons in thumb reach.
class StickyActions extends StatelessWidget {
  const StickyActions({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.vfBg,
      border: Border(top: BorderSide(color: context.vfLine)),
    ),
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: child,
    ),
  );
}

/// Button styles the design names: a solid success, a solid destructive and
/// an outlined destructive.
class VfButtons {
  const VfButtons._();

  static ButtonStyle success() => FilledButton.styleFrom(
    backgroundColor: VfColors.okSolid,
    foregroundColor: Colors.white,
  );

  static ButtonStyle destructive() => FilledButton.styleFrom(
    backgroundColor: VfColors.badSolid,
    foregroundColor: Colors.white,
  );

  static ButtonStyle destructiveOutline(BuildContext context) =>
      OutlinedButton.styleFrom(
        foregroundColor: context.vfBad,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: context.vfBad.withValues(alpha: .6)),
      );
}

/// The product mark: a brand tile with a check-seal, then the name.
class VfLogo extends StatelessWidget {
  const VfLogo({super.key, this.size = 34, this.fontSize = 19});

  final double size, fontSize;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: VfColors.accent500,
          borderRadius: BorderRadius.circular(size * .28),
        ),
        child: Icon(
          Icons.verified_rounded,
          size: size * .56,
          color: VfColors.onAccent,
        ),
      ),
      SizedBox(width: size * .32),
      Text(
        'app.name'.tr,
        style: TextStyle(
          fontFamily: VfTheme.fontFamily,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: context.vfInk,
        ),
      ),
    ],
  );
}

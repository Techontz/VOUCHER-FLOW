import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The web client's `.btn` family.
enum VfButtonVariant { primary, secondary, ghost, danger, dangerSolid }

/// A VouchFlow button: `btn-primary`, `btn-secondary`, `btn-ghost`,
/// `btn-danger` and `btn-danger-solid`, with an optional leading icon and a
/// loading state that keeps the button's width.
class VouchFlowButton extends StatelessWidget {
  const VouchFlowButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.variant = VfButtonVariant.primary,
    this.loading = false,
    this.expand = false,
    this.height = VfSize.controlH,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final VfButtonVariant variant;
  final bool loading;
  final bool expand;
  final double height;

  /// The web's `btn-sm`: 36px, tighter padding, 14px type.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final enabled = onPressed != null && !loading;
    final h = compact ? 36.0 : height;

    final (Color bg, Color fg, Color border) = switch (variant) {
      VfButtonVariant.primary => (t.primary, Colors.white, t.primary),
      VfButtonVariant.secondary => (t.surface3, t.text, Colors.transparent),
      VfButtonVariant.ghost => (Colors.transparent, t.text2, Colors.transparent),
      VfButtonVariant.danger => (
        t.dangerSoft,
        t.dangerStrong,
        Colors.transparent,
      ),
      VfButtonVariant.dangerSolid => (t.dangerStrong, Colors.white, t.dangerStrong),
    };

    final disabledSolid =
        !enabled &&
        (variant == VfButtonVariant.primary ||
            variant == VfButtonVariant.dangerSolid);

    final child = loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: disabledSolid || variant == VfButtonVariant.primary
                  ? Colors.white
                  : t.text2,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: compact ? 16 : 18, color: disabledSolid ? Colors.white : fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.bodyStrong.copyWith(
                    fontSize: compact ? 14 : 15,
                    fontWeight: variant == VfButtonVariant.secondary ||
                            variant == VfButtonVariant.ghost
                        ? FontWeight.w500
                        : FontWeight.w600,
                    color: disabledSolid ? Colors.white : fg,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(trailingIcon, size: compact ? 16 : 18, color: disabledSolid ? Colors.white : fg),
              ],
            ],
          );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        height: h,
        width: expand ? double.infinity : null,
        child: Material(
          color: disabledSolid ? t.borderStrong : bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 12 : 16),
            side: BorderSide(color: disabledSolid ? t.borderStrong : border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            overlayColor: WidgetStatePropertyAll(
              variant == VfButtonVariant.primary
                  ? t.primaryHover.withValues(alpha: .35)
                  : t.surface3,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
              child: Center(widthFactor: 1, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// The outline (`btn-secondary`) button, named for callers that read better
/// with it.
class VouchFlowOutlinedButton extends VouchFlowButton {
  const VouchFlowOutlinedButton({
    super.key,
    required super.label,
    super.onPressed,
    super.icon,
    super.trailingIcon,
    super.loading,
    super.expand,
    super.compact,
  }) : super(variant: VfButtonVariant.secondary);
}

/// A square icon-only button (`btn-icon`), with a required accessible label.
class VouchFlowIconButton extends StatelessWidget {
  const VouchFlowIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
    this.size = VfSize.controlH,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;

  /// A solid primary square (the top bar's "+").
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: filled ? t.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(size),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Icon(
              icon,
              size: 21,
              color: filled ? Colors.white : (color ?? t.text2),
              semanticLabel: tooltip,
            ),
          ),
        ),
      ),
    );
  }
}

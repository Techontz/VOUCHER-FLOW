import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import 'buttons.dart';

/// The web's `.vf-panel` / `.card`: surface, 1px border, radius 10, soft
/// shadow; optional head with a title, subtitle and actions.
class VouchFlowCard extends StatelessWidget {
  const VouchFlowCard({
    super.key,
    this.title,
    this.subtitle,
    this.actions,
    this.child,
    this.padding = const EdgeInsets.all(VfSize.cardPad),
    this.onTap,
    this.radius = VfSize.radiusL,
    this.color,
    this.borderColor,
  });

  final String? title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final hasHead = title != null || (actions?.isNotEmpty ?? false);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasHead)
          Container(
            padding: EdgeInsets.fromLTRB(16, 16, 12, child == null ? 16 : 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(title!, style: VfType.sectionTitle.copyWith(color: t.text, fontSize: 17)),
                    ],
                  ),
                ),
                ...?actions,
              ],
            ),
          ),
        if (child != null) Padding(padding: padding, child: child),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: color ?? t.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? (t.isDark ? t.border : Colors.transparent),
        ),
        boxShadow: t.cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// A page heading: optional back link, uppercase kicker, bold title, a
/// secondary line and actions — the web's `.vf-pagehead`.
class VouchFlowPageHeader extends StatelessWidget {
  const VouchFlowPageHeader({
    super.key,
    required this.title,
    this.kicker,
    this.subtitle,
    this.actions,
    this.backLabel,
    this.onBack,
  });

  final String title;
  final String? kicker;
  final String? subtitle;
  final List<Widget>? actions;
  final String? backLabel;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (backLabel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
              borderRadius: BorderRadius.circular(VfSize.radiusS),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsRegular.arrowLeft, size: 15, color: t.muted),
                    const SizedBox(width: 6),
                    Text(backLabel!, style: VfType.small.copyWith(color: t.muted, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
        // An app shows the title alone: the kicker and the explanatory line
        // the web prints under it are left out on the phone.
        Text(
          title,
          style: VfType.pageTitle.copyWith(
            color: t.text,
            fontSize: 28,
            letterSpacing: -.7,
          ),
        ),
        if (actions != null && actions!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: actions!),
        ],
      ],
    );
  }
}

/// A section heading inside a page.
class VouchFlowSectionHeader extends StatelessWidget {
  const VouchFlowSectionHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: VfType.sectionTitle.copyWith(color: t.text)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// An uppercase eyebrow label ("STEP 1 OF 5", "LIVE PREVIEW").
class VouchFlowEyebrow extends StatelessWidget {
  const VouchFlowEyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: VfType.eyebrow.copyWith(color: color ?? context.vf.muted));
}

/// The web's `.badge`: a 24px pill in a status tone (`tag-*`).
class VouchFlowStatusBadge extends StatelessWidget {
  const VouchFlowStatusBadge({super.key, required this.label, this.tag = 'tag-neutral', this.large = false});

  final String label;
  final String tag;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 14 : 11, vertical: large ? 5 : 3),
      decoration: BoxDecoration(
        color: VfStatus.background(tag, b),
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: VfType.meta.copyWith(
          fontSize: large ? 13 : 12,
          fontWeight: FontWeight.w500,
          color: VfStatus.foreground(tag, b),
        ),
      ),
    );
  }
}

/// A round avatar: the image when there is one, else initials on the primary.
class VouchFlowAvatar extends StatelessWidget {
  const VouchFlowAvatar({super.key, required this.initials, this.size = 40, this.imageUrl, this.square = false});

  final String initials;
  final double size;
  final String? imageUrl;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final radius = square ? BorderRadius.circular(VfSize.radiusM) : BorderRadius.circular(size);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: imageUrl != null ? Colors.white : t.primary,
        borderRadius: radius,
      ),
      padding: imageUrl != null ? const EdgeInsets.all(3) : null,
      alignment: Alignment.center,
      child: imageUrl != null
          ? Image.network(
              imageUrl!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _initials(t),
            )
          : _initials(t),
    );
  }

  Widget _initials(VfTokens t) => Text(
    initials,
    style: VfType.bodyStrong.copyWith(fontSize: size * .37, color: Colors.white, height: 1),
  );
}

/// Tones for stat cards and alerts, as the web's `tone-*`.
enum VfTone { primary, info, ok, warn, bad, neutral }

extension VfToneColors on VfTone {
  (Color fg, Color bg) colors(VfTokens t) => switch (this) {
    VfTone.primary => (t.primary, t.primarySoftStrong),
    VfTone.info => (t.infoStrong, t.infoSoft),
    VfTone.ok => (t.successStrong, t.successSoft),
    VfTone.warn => (t.warningStrong, t.warningSoft),
    VfTone.bad => (t.dangerStrong, t.dangerSoft),
    VfTone.neutral => (t.text2, t.surface3),
  };
}

/// The web's `.vf-kpi`: label, big figure, a quieter line, a round tinted
/// icon. Tone colours the figure (info/ok/warn/bad) as on the dashboard.
class VouchFlowStatCard extends StatelessWidget {
  const VouchFlowStatCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    this.tone = VfTone.primary,
    this.onTap,
  });

  final String label;
  final String value;
  final String? sub;
  final IconData? icon;
  final VfTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (fg, bg) = tone.colors(t);
    final figure = tone == VfTone.primary || tone == VfTone.neutral ? t.text : fg;
    return VouchFlowCard(
      onTap: onTap,
      radius: VfSize.radiusXl,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: VfType.small.copyWith(color: t.text2, fontWeight: FontWeight.w500))),
              if (icon != null)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(icon, size: 18, color: tone == VfTone.primary ? t.primary : fg),
                ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: VfType.figureS.copyWith(color: figure, fontSize: 24)),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!, style: VfType.meta.copyWith(color: t.muted, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

/// A labelled value, the web's `.vf-dl` row.
class VouchFlowKeyValue extends StatelessWidget {
  const VouchFlowKeyValue({super.key, required this.label, required this.value, this.mono = false, this.strong = false});

  final String label;
  final String value;
  final bool mono;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: VfType.meta.copyWith(color: t.muted, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            value.isEmpty ? '—' : value,
            style: (strong ? VfType.bodyStrong : VfType.body).copyWith(
              color: t.text,
              fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// The web's empty state: a soft icon plate, a title, a line and an action.
class VouchFlowEmptyState extends StatelessWidget {
  const VouchFlowEmptyState({
    super.key,
    required this.title,
    this.body,
    this.icon = PhosphorIconsRegular.tray,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? body;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: t.primarySoft, shape: BoxShape.circle),
            child: Icon(icon, size: 32, color: t.primary),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: VfType.cardTitle.copyWith(color: t.text)),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, textAlign: TextAlign.center, style: VfType.small.copyWith(color: t.muted)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            VouchFlowButton(label: actionLabel!, onPressed: onAction, variant: VfButtonVariant.secondary),
          ],
        ],
      ),
    );
  }
}

/// Loading placeholders in the web's shimmer-block style.
class VouchFlowLoadingState extends StatefulWidget {
  const VouchFlowLoadingState({super.key, this.rows = 4, this.rowHeight = 88});

  final int rows;
  final double rowHeight;

  @override
  State<VouchFlowLoadingState> createState() => _VouchFlowLoadingStateState();
}

class _VouchFlowLoadingStateState extends State<VouchFlowLoadingState> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final c = Color.lerp(t.surface3, t.surface2, _c.value)!;
          return Column(
            children: [
              for (var i = 0; i < widget.rows; i++)
                Container(
                  height: widget.rowHeight,
                  margin: const EdgeInsets.only(bottom: VfSize.gap),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(VfSize.radiusXl),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A failed load, with the server's wording and a retry.
class VouchFlowErrorState extends StatelessWidget {
  const VouchFlowErrorState({super.key, required this.message, this.onRetry, this.retryLabel = 'Try again'});

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowCard(
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: t.dangerSoft, shape: BoxShape.circle),
            child: Icon(PhosphorIconsRegular.warningCircle, color: t.dangerStrong),
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: VfType.body.copyWith(color: t.text)),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            VouchFlowButton(label: retryLabel, onPressed: onRetry, variant: VfButtonVariant.secondary, icon: PhosphorIconsRegular.arrowClockwise),
          ],
        ],
      ),
    );
  }
}

/// An inline alert (the web's `.vf-alert` / `.vf-note`).
class VouchFlowAlert extends StatelessWidget {
  const VouchFlowAlert({super.key, required this.message, this.title, this.tone = VfTone.info, this.icon, this.action});

  final String message;
  final String? title;
  final VfTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (fg, bg) = tone.colors(t);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        border: Border.all(color: fg.withValues(alpha: .25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? PhosphorIconsRegular.info, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: VfType.bodyStrong.copyWith(color: t.text)),
                Text(message, style: VfType.small.copyWith(color: t.text2)),
                if (action != null) ...[const SizedBox(height: 10), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/profile_models.dart';
import '../../widgets/vf/vf.dart';
import '../approvals/list_bits.dart';
import '../dashboard/dash_bits.dart' show dashDateTime;

export '../approvals/list_bits.dart' show AppListGroup, AppIconTile;

/// One settings row: a tinted icon tile, the label, an optional value or
/// control on the right, and a chevron when it opens something.
class ProfileSettingsRow extends StatelessWidget {
  const ProfileSettingsRow({
    super.key,
    required this.icon,
    required this.label,
    required this.tint,
    this.value,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.chevron = true,
  });

  final IconData icon;
  final String label;

  /// (foreground, background) of the icon tile.
  final (Color, Color) tint;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (fg, bg) = tint;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
        child: Row(
          children: [
            AppIconTile(icon: icon, fg: fg, bg: bg, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VfType.body.copyWith(
                  color: danger ? t.dangerStrong : t.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: VfType.small.copyWith(color: t.muted),
                ),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (chevron && onTap != null && !danger) ...[
              const SizedBox(width: 4),
              Icon(PhosphorIconsRegular.caretRight, size: 18, color: t.faint),
            ],
          ],
        ),
      ),
    );
  }
}

/// A form's fields on a rounded card, evenly spaced.
class ProfileFormCard extends StatelessWidget {
  const ProfileFormCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusXl),
        border: Border.all(color: t.isDark ? t.border : Colors.transparent),
        boxShadow: t.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A pushed profile page's scrolling body, its primary action last.
class ProfilePageBody extends StatelessWidget {
  const ProfilePageBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(VfSize.pagePad, 8, VfSize.pagePad, 28),
      children: children,
    ),
  );
}

/// Two fields side by side where there is room; stacked on a phone.
class ProfileFormRow extends StatelessWidget {
  const ProfileFormRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 520) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              children[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: children[i]),
          ],
        ],
      );
    },
  );
}

/// A pill of mutually exclusive choices, filling the width.
class ProfileSegmented<T> extends StatelessWidget {
  const ProfileSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;

  /// (value, label, icon, enabled)
  final List<(T, String, IconData?, bool)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: Semantics(
                selected: o.$1 == value,
                button: true,
                enabled: o.$4,
                child: Material(
                  color: o.$1 == value ? t.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(VfSize.radiusM + 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(VfSize.radiusM + 2),
                    onTap: o.$4 ? () => onChanged(o.$1) : null,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 40),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: o.$1 == value
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                VfSize.radiusM + 2,
                              ),
                              boxShadow: t.cardShadow,
                            )
                          : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (o.$3 != null) ...[
                            Icon(
                              o.$3,
                              size: 16,
                              color: o.$1 == value ? t.text : t.muted,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              o.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VfType.label.copyWith(
                                fontSize: 13.5,
                                color: !o.$4
                                    ? t.faint
                                    : o.$1 == value
                                    ? t.text
                                    : t.text2,
                                fontWeight: o.$1 == value
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One signed-in device, with Revoke — or "This device".
class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.session, required this.onRevoke});

  final ProfileSession session;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final s = session;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          AppIconTile(
            icon: PhosphorIconsFill.deviceMobile,
            fg: s.isCurrent ? t.successStrong : t.text2,
            bg: s.isCurrent ? t.successSoft : t.surface3,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.device,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.body.copyWith(
                    color: t.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  dashDateTime(s.lastUsedAt ?? s.createdAt),
                  style: VfType.meta.copyWith(color: t.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (s.isCurrent)
            VouchFlowStatusBadge(
              label: 'profile.thisDevice'.tr,
              tag: 'tag-accent',
            )
          else
            TextButton(
              onPressed: onRevoke,
              child: Text(
                'profile.revoke'.tr,
                style: VfType.label.copyWith(
                  color: t.dangerStrong,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/profile_models.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDateTime;

/// A `.vf-panel` holding a form, with the web's `.app-form-foot` below.
class ProfilePanel extends StatelessWidget {
  const ProfilePanel({super.key, required this.child, this.footer});

  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        border: Border.all(color: t.border),
        boxShadow: t.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.all(16), child: child),
          ?footer,
        ],
      ),
    );
  }
}

/// The form's foot: a secondary action at the start, the primary at the end.
class ProfileFormFoot extends StatelessWidget {
  const ProfileFormFoot({super.key, this.start, required this.end});

  final Widget? start;
  final Widget end;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (start != null) Flexible(child: start!) else const SizedBox(),
          const SizedBox(width: 10),
          Flexible(flex: 2, child: end),
        ],
      ),
    );
  }
}

/// The web's `FormSection`: a heading, a line of explanation, the fields.
class ProfileFormSection extends StatelessWidget {
  const ProfileFormSection({
    super.key,
    required this.title,
    this.description,
    required this.children,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: VfType.cardTitle.copyWith(color: t.text)),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(description!, style: VfType.small.copyWith(color: t.muted)),
        ],
        for (final child in children) ...[const SizedBox(height: 16), child],
      ],
    );
  }
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

/// A file input: a "Choose" button, then the file's name (and a preview).
class ProfileFilePicker extends StatelessWidget {
  const ProfileFilePicker({
    super.key,
    required this.buttonLabel,
    required this.fileName,
    required this.onPick,
    this.preview,
  });

  final String buttonLabel;
  final String fileName;
  final VoidCallback onPick;
  final Uint8List? preview;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        border: Border.all(color: t.inputBorder),
      ),
      child: Row(
        children: [
          VouchFlowButton(
            label: buttonLabel,
            icon: PhosphorIconsRegular.uploadSimple,
            variant: VfButtonVariant.secondary,
            compact: true,
            onPressed: onPick,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VfType.small.copyWith(color: t.muted),
            ),
          ),
          if (preview != null) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(VfSize.radiusS),
              child: Image.memory(
                preview!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The web's `.seg`: a pill of mutually exclusive choices.
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: t.surface3,
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          border: Border.all(color: t.border),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options)
                Semantics(
                  selected: o.$1 == value,
                  button: true,
                  enabled: o.$4,
                  child: Material(
                    color: o.$1 == value ? t.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(VfSize.radiusM),
                    elevation: 0,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(VfSize.radiusM),
                      onTap: o.$4 ? () => onChanged(o.$1) : null,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: o.$1 == value
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  VfSize.radiusM,
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
                            Text(
                              o.$2,
                              style: VfType.label.copyWith(
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
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One signed-in device, with Revoke — or "This device".
class SessionRow extends StatelessWidget {
  const SessionRow({
    super.key,
    required this.session,
    required this.onRevoke,
    this.last = false,
  });

  final ProfileSession session;
  final VoidCallback onRevoke;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final s = session;
    final name = s.isCurrent
        ? '${s.device} · ${'profile.thisDevice'.tr}'
        : s.device;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.deviceMobile, size: 18, color: t.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.body.copyWith(
                    color: t.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  dashDateTime(s.lastUsedAt ?? s.createdAt),
                  style: VfType.meta.copyWith(color: t.muted, fontSize: 13),
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
            VouchFlowButton(
              label: 'profile.revoke'.tr,
              variant: VfButtonVariant.ghost,
              compact: true,
              onPressed: onRevoke,
            ),
        ],
      ),
    );
  }
}

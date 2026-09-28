import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../widgets/common.dart' show showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import '../shell/shell_page.dart';

/// Pieces shared by the company-administration pages: the settings menu the
/// web draws above every admin page on a phone, the page frame, pagination,
/// badges, meters and the web's `reportError`.

/// Which part of /settings is showing — the web keeps it in the address
/// (#workflow, #types, #company); here it lives beside the shell's route.
class AdminSettings {
  AdminSettings._();

  static final section = 'workflow'.obs;
}

class _SettingsLink {
  const _SettingsLink(this.href, this.label, this.icon, [this.hash]);
  final String href, label;
  final IconData icon;
  final String? hash;
}

/// The web's COMPANY_SETTINGS, group by group.
const _companySettings = [
  [
    _SettingsLink(
      '/settings',
      'admin.companyProfile',
      PhosphorIconsRegular.buildings,
      'company',
    ),
    _SettingsLink('/branding', 'admin.branding', PhosphorIconsRegular.palette),
    _SettingsLink(
      '/subscription',
      'admin.subscription',
      PhosphorIconsRegular.crownSimple,
    ),
  ],
  [
    _SettingsLink(
      '/settings',
      'admin.approvalWorkflow',
      PhosphorIconsRegular.flowArrow,
      'workflow',
    ),
    _SettingsLink(
      '/settings',
      'admin.voucherSettings',
      PhosphorIconsRegular.receipt,
      'types',
    ),
  ],
  [
    _SettingsLink(
      '/employees',
      'admin.employees',
      PhosphorIconsRegular.usersThree,
    ),
    _SettingsLink(
      '/departments',
      'admin.departments',
      PhosphorIconsRegular.treeStructure,
    ),
    _SettingsLink('/audit', 'admin.auditLogs', PhosphorIconsRegular.scroll),
  ],
];

/// The company settings menu: a sideways-scrolling row of links, as the web
/// draws its settings sidebar under 980px. Only a company administrator has
/// the whole area; everyone else sees the page alone.
class AdminSettingsNav extends StatefulWidget {
  const AdminSettingsNav({super.key, required this.current});

  /// The shell route this page is (e.g. '/employees').
  final String current;

  @override
  State<AdminSettingsNav> createState() => _AdminSettingsNavState();
}

class _AdminSettingsNavState extends State<AdminSettingsNav> {
  final _activeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: .3);
    });
  }

  void _open(_SettingsLink link) {
    if (link.hash != null) AdminSettings.section.value = link.hash!;
    if (Get.isRegistered<ShellController>()) {
      Get.find<ShellController>().go(link.href);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Obx(() {
      final section = AdminSettings.section.value;
      bool active(_SettingsLink l) =>
          l.href == widget.current && (l.hash == null || l.hash == section);
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final group in _companySettings)
                for (final link in group)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _NavLink(
                      key: active(link) ? _activeKey : null,
                      label: link.label.tr,
                      icon: link.icon,
                      active: active(link),
                      onTap: () => _open(link),
                    ),
                  ),
            ],
          ),
        ),
      );
    });
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({
    super.key,
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      selected: active,
      button: true,
      child: Material(
        color: active ? t.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        child: InkWell(
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: active ? t.primaryText : t.faint),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: VfType.label.copyWith(
                    fontSize: 15,
                    color: active ? t.primaryText : t.text2,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A company-administration page: the settings menu (company administrators
/// only), the page head, then the content — the web's SettingsLayout.
class AdminPageBody extends StatelessWidget {
  const AdminPageBody({
    super.key,
    required this.route,
    required this.title,
    this.subtitle,
    this.actions,
    required this.children,
    this.onRefresh,
    this.showNav = true,
  });

  final String route;
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final bool showNav;

  @override
  Widget build(BuildContext context) {
    final isCompanyAdmin =
        Get.isRegistered<SessionService>() &&
        Get.find<SessionService>().user.value?.role == 'company_admin';
    return VouchFlowPageBody(
      onRefresh: onRefresh,
      padding: const EdgeInsets.fromLTRB(
        VfSize.pagePad,
        12,
        VfSize.pagePad,
        32,
      ),
      children: [
        if (showNav && isCompanyAdmin)
          AdminSettingsNav(current: route)
        else
          const SizedBox(height: 8),
        VouchFlowPageHeader(title: title, subtitle: subtitle),
        if (actions != null && actions!.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (var i = 0; i < actions!.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: actions![i]),
          ],
        ],
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

/// The web's reportError: the API's message (and its first field error),
/// or the page's own fallback.
void adminReport(Object error, String fallback) {
  if (error is ApiException) {
    final first = error.errors.values.isEmpty
        ? null
        : error.errors.values.first.firstOrNull;
    showToast(
      error.message.isNotEmpty ? error.message : fallback,
      body: first != null && first != error.message ? first : null,
      kind: ToastKind.bad,
    );
    return;
  }
  showToast(fallback, body: '$error', kind: ToastKind.bad);
}

/// A readable message for a failed load.
String adminErrorText(Object error) =>
    error is ApiException ? error.message : 'admin.somethingWrong'.tr;

/// `{name}`-style placeholders, as the web's `.replace()` calls fill them.
String fill(String text, Map<String, Object?> values) {
  var out = text;
  values.forEach((k, v) => out = out.replaceAll('{$k}', '${v ?? ''}'));
  return out;
}

/// The web's badge tones, drawn with the shared status colours.
class AdminBadge extends StatelessWidget {
  const AdminBadge(this.label, {super.key, this.tone = VfTone.neutral});

  final String label;
  final VfTone tone;

  @override
  Widget build(BuildContext context) {
    final tag = switch (tone) {
      VfTone.ok => 'tag-accent',
      VfTone.bad => 'tag-accent-2',
      VfTone.info || VfTone.primary => 'tag-info',
      VfTone.warn => 'tag-warn',
      VfTone.neutral => 'tag-neutral',
    };
    return VouchFlowStatusBadge(label: label, tag: tag);
  }
}

/// The web's Pagination: "Showing 25 · Page 1 of 3", Back and Next.
class AdminPagination extends StatelessWidget {
  const AdminPagination({
    super.key,
    required this.page,
    required this.lastPage,
    required this.total,
    required this.onChange,
  });

  final int page, lastPage, total;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    if (lastPage <= 1) return const SizedBox.shrink();
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${'admin.showing'.tr} $total · ${'admin.page'.tr} $page ${'admin.of'.tr} $lastPage',
            textAlign: TextAlign.center,
            style: VfType.small.copyWith(color: t.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: VouchFlowButton(
                  label: 'admin.back'.tr,
                  icon: PhosphorIconsRegular.caretLeft,
                  variant: VfButtonVariant.secondary,
                  compact: true,
                  onPressed: page <= 1 ? null : () => onChange(page - 1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: VouchFlowButton(
                  label: 'admin.next'.tr,
                  trailingIcon: PhosphorIconsRegular.caretRight,
                  variant: VfButtonVariant.secondary,
                  compact: true,
                  onPressed: page >= lastPage ? null : () => onChange(page + 1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The web's Meter: a thin bar, red once a limit is reached.
class AdminMeter extends StatelessWidget {
  const AdminMeter({super.key, required this.percent, this.exceeded = false});

  final int? percent;
  final bool exceeded;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final p = ((percent ?? 0).clamp(2, 100)) / 100;
    return Semantics(
      value: '${percent ?? 0}%',
      child: Container(
        height: 8,
        decoration: BoxDecoration(
          color: t.surface3,
          borderRadius: BorderRadius.circular(VfSize.radiusPill),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: p,
          child: Container(
            decoration: BoxDecoration(
              color: exceeded ? t.dangerStrong : t.primary,
              borderRadius: BorderRadius.circular(VfSize.radiusPill),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled switch (the web's `.switch`), 44px tall.
class AdminSwitch extends StatelessWidget {
  const AdminSwitch({
    super.key,
    required this.label,
    required this.value,
    this.onChanged,
    this.tooltip,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final row = InkWell(
      borderRadius: BorderRadius.circular(VfSize.radiusL),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: value, onChanged: onChanged),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: VfType.label.copyWith(
                  fontSize: 15,
                  color: onChanged == null ? t.muted : t.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return tooltip == null ? row : Tooltip(message: tooltip!, child: row);
  }
}

/// A checkbox with its label (the web's `label.radio` with a checkbox).
class AdminCheck extends StatelessWidget {
  const AdminCheck({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return InkWell(
      borderRadius: BorderRadius.circular(VfSize.radiusM),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged == null
                  ? null
                  : (v) => onChanged!(v ?? false),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label, style: VfType.body.copyWith(color: t.text)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A person: avatar with initials, a bold name and a line beneath.
class AdminPerson extends StatelessWidget {
  const AdminPerson({
    super.key,
    required this.initials,
    required this.name,
    this.sub,
    this.trailing,
  });

  final String initials, name;
  final String? sub;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Row(
      children: [
        VouchFlowAvatar(initials: initials.isEmpty ? '?' : initials, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: VfType.bodyStrong.copyWith(color: t.text),
              ),
              if (sub != null && sub!.isNotEmpty)
                Text(
                  sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VfType.small.copyWith(color: t.muted),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Label on the left, value on the right: one line of a list card.
class AdminLine extends StatelessWidget {
  const AdminLine({
    super.key,
    required this.label,
    required this.value,
    this.strong = false,
    this.valueWidget,
  });

  final String label;
  final String value;
  final bool strong;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: VfType.small.copyWith(color: t.muted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  valueWidget ??
                  Text(
                    value.isEmpty ? '—' : value,
                    textAlign: TextAlign.right,
                    style: (strong ? VfType.bodyStrong : VfType.small).copyWith(
                      color: t.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a stateful form as the web's dialog does on a phone: a bottom sheet
/// with an icon, title, fields and actions. [builder] receives a setState.
Future<T?> showAdminSheet<T>(
  BuildContext context,
  Widget Function(BuildContext context, StateSetter setState) builder,
) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => StatefulBuilder(builder: builder),
  );
}

/// The web's `Note`: a quiet info line with an icon.
class AdminNote extends StatelessWidget {
  const AdminNote(this.text, {super.key, this.tone = VfTone.info});

  final String text;
  final VfTone tone;

  @override
  Widget build(BuildContext context) => VouchFlowAlert(
    message: text,
    tone: tone,
    icon: tone == VfTone.warn
        ? PhosphorIconsRegular.warning
        : PhosphorIconsRegular.info,
  );
}

/// A small count pill beside a panel title (the web's `.vf-count`).
class AdminCount extends StatelessWidget {
  const AdminCount(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
      ),
      child: Text(
        '$count',
        style: VfType.meta.copyWith(
          color: t.text2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

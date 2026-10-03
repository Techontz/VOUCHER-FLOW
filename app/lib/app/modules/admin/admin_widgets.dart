import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../widgets/common.dart' show showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import '../shell/shell_page.dart';

/// Pieces shared by the company-administration pages: the settings chips,
/// the page frame (big title, one round action, an optional sticky save
/// bar), app list rows, grouped sections, option and detail sheets,
/// pagination, badges, meters and the web's `reportError`.

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

/// The web's COMPANY_SETTINGS, in order.
const _companySettings = [
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
];

/// The company settings menu: a sideways-scrolling row of rounded chips.
/// Only a company administrator has the whole area; everyone else sees the
/// page alone.
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
    return Obx(() {
      final section = AdminSettings.section.value;
      bool active(_SettingsLink l) =>
          l.href == widget.current && (l.hash == null || l.hash == section);
      return SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          // Bleed to the screen edges, as a native chip rail does.
          padding: const EdgeInsets.symmetric(horizontal: VfSize.pagePad),
          children: [
            for (final link in _companySettings)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _NavChip(
                  key: active(link) ? _activeKey : null,
                  label: link.label.tr,
                  icon: link.icon,
                  active: active(link),
                  onTap: () => _open(link),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({
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
        color: active ? t.primary : t.surface,
        shape: StadiumBorder(
          side: active || !t.isDark
              ? BorderSide.none
              : BorderSide(color: t.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: active ? Colors.white : t.muted),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: VfType.label.copyWith(
                    fontSize: 14,
                    color: active ? Colors.white : t.text2,
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

/// A company-administration page: the settings chips (company
/// administrators only), a big title with one round action beside it, the
/// content, and — for a form — a sticky save bar at the bottom.
class AdminPageBody extends StatelessWidget {
  const AdminPageBody({
    super.key,
    required this.route,
    required this.title,
    this.action,
    required this.children,
    this.onRefresh,
    this.showNav = true,
    this.showTitle = true,
    this.bottomBar,
  });

  final String route;
  final String title;

  /// False when an app bar above already names the page.
  final bool showTitle;

  /// The page's primary action — an [AdminRoundAction] or a compact pill.
  final Widget? action;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final bool showNav;

  /// Pinned under the scrolling content (an [AdminSaveBar]).
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final isCompanyAdmin =
        Get.isRegistered<SessionService>() &&
        Get.find<SessionService>().user.value?.role == 'company_admin';
    final nav = showNav && isCompanyAdmin;
    const pad = EdgeInsets.symmetric(horizontal: VfSize.pagePad);
    final body = VouchFlowPageBody(
      onRefresh: onRefresh,
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 32),
      children: [
        if (nav) ...[
          AdminSettingsNav(current: route),
          const SizedBox(height: 18),
        ],
        if (showTitle) ...[
          Padding(
            padding: pad,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.pageTitle.copyWith(
                      color: t.text,
                      fontSize: 28,
                      letterSpacing: -.7,
                    ),
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 12), action!],
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        for (final c in children) Padding(padding: pad, child: c),
      ],
    );
    if (bottomBar == null) return body;
    return Column(
      children: [
        Expanded(child: body),
        bottomBar!,
      ],
    );
  }
}

/// The page's primary action: a round primary button beside the title.
/// [label] is its accessible name and tooltip.
class AdminRoundAction extends StatelessWidget {
  const AdminRoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: onPressed == null ? t.borderStrong : t.primary,
          shape: const CircleBorder(),
          elevation: 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(icon, size: 22, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// A sticky bottom bar holding a page's save button.
class AdminSaveBar extends StatelessWidget {
  const AdminSaveBar({super.key, required this.child, this.leading});

  final Widget child;

  /// A quiet note to the left (e.g. "Unsaved changes").
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? .35 : .06),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VfSize.pagePad,
            12,
            VfSize.pagePad,
            12,
          ),
          child: leading == null
              ? child
              : Row(
                  children: [
                    Expanded(child: leading!),
                    const SizedBox(width: 12),
                    child,
                  ],
                ),
        ),
      ),
    );
  }
}

/// What a page's sticky save bar needs from the form below it: whether
/// there is anything to save, whether a save is running, and the save.
/// Safe to update from a build — the bar hears about it after the frame.
class AdminSaveState extends ChangeNotifier {
  bool ready = false, busy = false, dirty = true;
  VoidCallback? onSave;

  void update({bool? ready, bool? busy, bool? dirty, VoidCallback? onSave}) {
    final changed =
        (ready != null && ready != this.ready) ||
        (busy != null && busy != this.busy) ||
        (dirty != null && dirty != this.dirty);
    this.ready = ready ?? this.ready;
    this.busy = busy ?? this.busy;
    this.dirty = dirty ?? this.dirty;
    this.onSave = onSave ?? this.onSave;
    if (!changed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else if (!_disposed) {
      notifyListeners();
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A short section label above a rounded card — the grouped-form look.
class AdminSection extends StatelessWidget {
  const AdminSection({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final String label;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: VfType.label.copyWith(
                    color: t.muted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        VouchFlowCard(radius: VfSize.radiusXl, padding: padding, child: child),
      ],
    );
  }
}

/// Fields stacked with even gaps inside an [AdminSection].
class AdminFields extends StatelessWidget {
  const AdminFields(this.children, {super.key, this.gap = 14});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(height: gap),
        children[i],
      ],
    ],
  );
}

/// A tinted rounded icon tile — the leading mark of a list row.
class AdminIconTile extends StatelessWidget {
  const AdminIconTile(
    this.icon, {
    super.key,
    this.tone = VfTone.primary,
    this.size = 44,
  });

  final IconData icon;
  final VfTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (fg, bg) = tone == VfTone.primary
        ? (t.primaryText, t.primarySoftStrong)
        : tone.colors(t);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
      ),
      child: Icon(icon, size: size * .48, color: fg),
    );
  }
}

/// An app list row in its own rounded card: a leading avatar or icon tile,
/// a bold title, one muted line and a small trailing pill or chevron.
class AdminListRow extends StatelessWidget {
  const AdminListRow({
    super.key,
    required this.leading,
    required this.title,
    this.meta,
    this.trailing,
    this.onTap,
    this.semanticLabel,
  });

  final Widget leading;
  final String title;
  final String? meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        label: semanticLabel,
        button: onTap != null,
        child: VouchFlowCard(
          radius: VfSize.radiusXl,
          onTap: onTap,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VfType.bodyStrong.copyWith(color: t.text),
                    ),
                    if (meta != null && meta!.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        meta!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VfType.meta.copyWith(
                          color: t.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// The quiet chevron at the end of a tappable row.
class AdminChevron extends StatelessWidget {
  const AdminChevron({super.key});

  @override
  Widget build(BuildContext context) =>
      Icon(PhosphorIconsRegular.caretRight, size: 16, color: context.vf.faint);
}

/// A filter chip that shows its current choice and opens a sheet of
/// options (role, department, action …).
class AdminSelectChip extends StatelessWidget {
  const AdminSelectChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.onClear,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  /// Shown as an × inside an active chip.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final fg = active ? t.primaryText : t.text2;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? t.primarySoftStrong : t.surface,
        shape: StadiumBorder(
          side: active || !t.isDark
              ? BorderSide.none
              : BorderSide(color: t.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: EdgeInsets.only(
              left: 14,
              right: active && onClear != null ? 4 : 12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.label.copyWith(
                      fontSize: 14,
                      color: fg,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (active && onClear != null)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).deleteButtonTooltip,
                      icon: Icon(PhosphorIconsBold.x, size: 13, color: fg),
                      onPressed: onClear,
                    ),
                  )
                else
                  Icon(PhosphorIconsBold.caretDown, size: 12, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill search field: a soft fill, no outline, a magnifier and a clear
/// button once something is typed.
class AdminSearchField extends StatefulWidget {
  const AdminSearchField({
    super.key,
    required this.placeholder,
    this.controller,
    this.onChanged,
  });

  final String placeholder;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  State<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends State<AdminSearchField> {
  late final TextEditingController _c =
      widget.controller ?? TextEditingController();

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    const pill = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(VfSize.radiusPill)),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: _c,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      cursorColor: t.primary,
      style: VfType.body.copyWith(color: t.text),
      decoration: InputDecoration(
        hintText: widget.placeholder,
        hintStyle: VfType.body.copyWith(color: t.placeholder),
        filled: true,
        // Light pages are already grey, so the field is white there.
        fillColor: t.isDark ? t.surface3 : t.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: pill,
        enabledBorder: pill,
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(VfSize.radiusPill),
          ),
          borderSide: BorderSide(color: t.primary, width: 1.5),
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(
            PhosphorIconsRegular.magnifyingGlass,
            size: 19,
            color: t.muted,
          ),
        ),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                icon: Icon(PhosphorIconsBold.xCircle, size: 18, color: t.faint),
                onPressed: () {
                  _c.clear();
                  widget.onChanged?.call('');
                },
              ),
      ),
    );
  }
}

/// A horizontal rail of chips, bleeding to the screen edges.
class AdminChipRail extends StatelessWidget {
  const AdminChipRail({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A sheet of single-choice options; returns the chosen value.
Future<T?> showAdminOptions<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
}) {
  return showVouchFlowBottomSheet<T>(
    context,
    title: title,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in options)
            Builder(
              builder: (ctx) {
                final t = ctx.vf;
                final on = o.$1 == selected;
                return Semantics(
                  selected: on,
                  inMutuallyExclusiveGroup: true,
                  button: true,
                  child: Material(
                    color: on ? t.primarySoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(VfSize.radiusL),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(VfSize.radiusL),
                      onTap: () => Navigator.of(ctx).pop(o.$1),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 50),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                o.$2,
                                style: VfType.body.copyWith(
                                  color: on ? t.primaryText : t.text,
                                  fontWeight: on
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (on)
                              Icon(
                                PhosphorIconsBold.check,
                                size: 17,
                                color: t.primaryText,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );
}

/// One action in an item sheet.
class AdminSheetAction {
  const AdminSheetAction(
    this.icon,
    this.label,
    this.onTap, {
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// The bottom sheet a list row opens: a header, the item's details and its
/// actions. The sheet closes before an action runs.
Future<void> showAdminItemSheet(
  BuildContext context, {
  required Widget header,
  List<Widget> details = const [],
  List<AdminSheetAction> actions = const [],
}) async {
  final chosen = await showModalBottomSheet<AdminSheetAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final t = ctx.vf;
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * .88,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: t.surface2,
                      borderRadius: BorderRadius.circular(VfSize.radiusL),
                    ),
                    child: Column(children: details),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final a in actions)
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(VfSize.radiusL),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(VfSize.radiusL),
                        onTap: () => Navigator.of(ctx).pop(a),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 52),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            children: [
                              AdminIconTile(
                                a.icon,
                                size: 36,
                                tone: a.danger ? VfTone.bad : VfTone.neutral,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  a.label,
                                  style: VfType.bodyStrong.copyWith(
                                    color: a.danger ? t.dangerStrong : t.text,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
  chosen?.onTap();
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

/// Pagination: round back and next buttons around "2 / 3".
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
    Widget round(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
      message: tip,
      child: Material(
        color: t.surface,
        shape: CircleBorder(
          side: t.isDark ? BorderSide(color: t.border) : BorderSide.none,
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 18,
              color: onTap == null ? t.faint : t.text,
              semanticLabel: tip,
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          round(
            PhosphorIconsBold.caretLeft,
            'admin.back'.tr,
            page <= 1 ? null : () => onChange(page - 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              '$page / $lastPage',
              semanticsLabel:
                  '${'admin.page'.tr} $page ${'admin.of'.tr} $lastPage',
              style: VfType.bodyStrong.copyWith(
                color: t.text2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          round(
            PhosphorIconsBold.caretRight,
            'admin.next'.tr,
            page >= lastPage ? null : () => onChange(page + 1),
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

/// A settings-style switch row: the label, then the switch at the end.
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
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: VfType.label.copyWith(
                  fontSize: 15,
                  color: onChanged == null ? t.muted : t.text,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Switch.adaptive(value: value, onChanged: onChanged),
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
    this.size = 38,
  });

  final String initials, name;
  final String? sub;
  final Widget? trailing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Row(
      children: [
        VouchFlowAvatar(
          initials: initials.isEmpty ? '?' : initials,
          size: size,
        ),
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

/// Label on the left, value on the right: one line of a details block.
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
      padding: const EdgeInsets.symmetric(vertical: 6),
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
                      fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
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

/// A small count pill beside a section label (the web's `.vf-count`).
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

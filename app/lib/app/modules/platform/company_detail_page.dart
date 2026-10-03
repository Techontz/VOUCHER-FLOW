import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/dev_hooks.dart';
import '../../core/theme.dart';
import '../../data/models/platform_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/platform_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import '../branding/voucher_template_panel.dart';
import 'company_tabs.dart';
import 'platform_widgets.dart';

/// One company, as the platform super admin sees it (web:
/// /platform/companies/[id]): its identity, the Edit branding / Change plan
/// / Suspend-Activate actions, and the nine tabs — each reading that
/// company's own data through the platform API.
///
/// Pushed with `Get.toNamed(Routes.platformCompany, arguments: companyId)`;
/// `{'id': companyId, 'tab': 'users'}` also opens a given tab.
class PlatformCompanyPage extends StatefulWidget {
  const PlatformCompanyPage({super.key});

  @override
  State<PlatformCompanyPage> createState() => _PlatformCompanyPageState();
}

const _tabs = <(String, IconData)>[
  ('overview', PhosphorIconsRegular.squaresFour),
  ('branding', PhosphorIconsRegular.palette),
  ('users', PhosphorIconsRegular.usersThree),
  ('departments', PhosphorIconsRegular.treeStructure),
  ('workflow', PhosphorIconsRegular.flowArrow),
  ('vouchers', PhosphorIconsRegular.receipt),
  ('payments', PhosphorIconsRegular.handCoins),
  ('subscription', PhosphorIconsRegular.crownSimple),
  ('activity', PhosphorIconsRegular.clockCounterClockwise),
];

class _PlatformCompanyPageState extends State<PlatformCompanyPage> {
  final _repo = PlatformRepository.to;
  final _scroll = ScrollController();
  late final int? _id;
  CompanyDetail? _detail;
  CompanyOverview? _overview;
  List<DepartmentRow>? _departments;
  List<PlatformPlan> _plans = const [];
  String? _error;
  String _tab = 'overview';
  Map<String, String>? _tabFilter;
  int _filterKey = 0;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    String? tab;
    if (args is int) {
      _id = args;
      tab = DevHooks.pushArgs['tab'];
    } else if (args is Map) {
      _id = int.tryParse('${args['id']}');
      tab = args['tab'] as String?;
    } else {
      _id = int.tryParse('$args');
    }
    if (tab != null && _tabs.any((x) => x.$1 == tab)) _tab = tab;
    _load();
    _repo
        .plans()
        .then((p) {
          if (mounted) setState(() => _plans = p);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _id;
    if (id == null) {
      setState(() => _error = 'platform.noResults'.tr);
      return;
    }
    setState(() => _error = null);
    await Future.wait([
      _repo
          .company(id)
          .then((d) {
            if (mounted) setState(() => _detail = d);
          })
          .catchError((Object e) {
            if (mounted) setState(() => _error = errorText(e));
          }),
      _repo
          .overview(id)
          .then((o) {
            if (mounted) setState(() => _overview = o);
          })
          .catchError((Object e) {
            if (mounted) setState(() => _error = errorText(e));
          }),
      _repo
          .departments(id)
          .then((d) {
            if (mounted) setState(() => _departments = d);
          })
          .catchError((_) {
            if (mounted) setState(() => _departments = const []);
          }),
    ]);
  }

  void _open(String tab, [Map<String, String>? filter]) {
    setState(() {
      _tabFilter = filter;
      _filterKey++;
      _tab = tab;
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _changePlan() async {
    final c = _detail?.company;
    if (c == null) return;
    final changed = await showVouchFlowDialog<bool>(
      context,
      dialog: VouchFlowDialog(
        icon: PhosphorIconsRegular.crownSimple,
        title: 'platform.changePlan'.tr,
        subtitle: 'platform.co.changePlanSub'.tr,
        child: _ChangePlanForm(company: c, plans: _plans),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _setStatus() async {
    final c = _detail?.company;
    if (c == null) return;
    final suspend = c.status != 'suspended';
    final done = await showVouchFlowDialog<bool>(
      context,
      dialog: VouchFlowDialog(
        icon: suspend
            ? PhosphorIconsRegular.prohibit
            : PhosphorIconsRegular.checkCircle,
        tone: suspend ? VfTone.warn : VfTone.ok,
        title:
            (suspend
                    ? 'platform.confirm.suspendNamed'
                    : 'platform.confirm.activateNamed')
                .trParams({'name': c.name}),
        subtitle: suspend
            ? 'platform.confirm.suspendSub'.tr
            : 'platform.confirm.activateSub'.tr,
        child: _StatusActions(company: c, suspend: suspend),
      ),
    );
    if (done == true) _load();
  }

  Future<void> _editBranding() async {
    final c = _detail?.company;
    if (c == null) return;
    final saved = await showVouchFlowDialog<bool>(
      context,
      dismissible: false,
      dialog: VouchFlowDialog(
        icon: PhosphorIconsRegular.paintBrush,
        title: 'platform.co.editBranding'.tr,
        subtitle: 'platform.co.brandSub'.trParams({'name': c.name}),
        child: _BrandingForm(company: c),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final o = _overview;
    Widget body;
    if (_error != null && d == null) {
      body = ListView(
        padding: const EdgeInsets.all(VfSize.pagePad),
        children: [
          VouchFlowErrorState(
            message: _error!,
            onRetry: _load,
            retryLabel: 'action.retry'.tr,
          ),
        ],
      );
    } else if (d == null || o == null) {
      body = ListView(
        padding: const EdgeInsets.all(VfSize.pagePad),
        children: const [VouchFlowLoadingState(rows: 6, rowHeight: 96)],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            VfSize.pagePad,
            16,
            VfSize.pagePad,
            32,
          ),
          children: [
            _Header(company: d.company),
            const SizedBox(height: 16),
            _actions(d.company),
            const SizedBox(height: 18),
            VouchFlowTabs(
              labels: [for (final x in _tabs) 'platform.co.tab.${x.$1}'.tr],
              icons: [for (final x in _tabs) x.$2],
              current: _tabs.indexWhere((x) => x.$1 == _tab),
              onChanged: (i) => _open(_tabs[i].$1),
            ),
            const SizedBox(height: 16),
            _tabBody(d, o),
          ],
        ),
      );
    }
    return VouchFlowPushedScaffold(
      title: 'platform.companies.title'.tr,
      body: body,
    );
  }

  Widget _actions(PlatformCompany c) {
    final suspended = c.status == 'suspended';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: VouchFlowButton(
                label: 'platform.co.editBranding'.tr,
                icon: PhosphorIconsRegular.paintBrush,
                variant: VfButtonVariant.secondary,
                onPressed: _editBranding,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: VouchFlowButton(
                label: 'platform.changePlan'.tr,
                icon: PhosphorIconsRegular.crownSimple,
                variant: VfButtonVariant.secondary,
                onPressed: _changePlan,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (c.status == 'pending') ...[
          VouchFlowButton(
            label: 'platform.approve'.tr,
            icon: PhosphorIconsRegular.sealCheck,
            onPressed: () async {
              if (await confirmApproveCompany(context, c)) _load();
            },
          ),
          const SizedBox(height: 10),
        ],
        suspended
            ? VouchFlowButton(
                label: 'platform.activate'.tr,
                icon: PhosphorIconsRegular.checkCircle,
                onPressed: _setStatus,
              )
            : VouchFlowButton(
                label: 'platform.suspend'.tr,
                icon: PhosphorIconsRegular.prohibit,
                variant: VfButtonVariant.danger,
                onPressed: _setStatus,
              ),
      ],
    );
  }

  Widget _tabBody(CompanyDetail d, CompanyOverview o) {
    final c = d.company;
    return switch (_tab) {
      'branding' => BrandingTab(
        company: c,
        onEdit: _editBranding,
        // The company's chosen design, rendered by the server exactly as its
        // vouchers print, with the platform's change control.
        voucherDesign: VoucherTemplatePanel(
          mode: 'platform',
          companyId: c.id,
          onChanged: (_) => _load(),
        ),
      ),
      'users' => UsersTab(
        key: ValueKey('users-$_filterKey'),
        companyId: c.id,
        departments: _departments ?? const [],
        roles: o.byRole.keys.toList(),
        initial: _tabFilter,
      ),
      'departments' => DepartmentsTab(
        departments: _departments,
        currency: o.currency,
        onOpen: _open,
      ),
      'workflow' => WorkflowTab(companyId: c.id),
      'vouchers' => VouchersTab(
        key: ValueKey('vouchers-$_filterKey'),
        companyId: c.id,
        departments: _departments ?? const [],
        currency: o.currency,
        initial: _tabFilter,
      ),
      'payments' => PaymentsTab(overview: o),
      'subscription' => SubscriptionTab(detail: d, onChangePlan: _changePlan),
      'activity' => ActivityTab(companyId: c.id),
      _ => OverviewTab(detail: d, overview: o, onOpen: _open),
    };
  }
}

/// The logo tile, status / plan / palette kicker, name and contact line.
class _Header extends StatelessWidget {
  const _Header({required this.company});

  final PlatformCompany company;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = company;
    final palette = PlatformPalette.of(c.colorTheme);
    final place = [c.city, c.region, c.country].whereType<String>().join(', ');
    final contact = [
      c.email,
      c.phone,
      if (place.isNotEmpty) place,
    ].whereType<String>().join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          padding: c.logoMarkUrl != null ? const EdgeInsets.all(6) : null,
          decoration: BoxDecoration(
            color: c.logoMarkUrl != null ? Colors.white : palette.primary,
            borderRadius: BorderRadius.circular(VfSize.radiusXl),
            border: Border.all(color: t.border),
          ),
          child: c.logoMarkUrl != null
              ? Image.network(
                  c.logoMarkUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text(
                    c.displayInitials,
                    style: VfType.cardTitle.copyWith(color: palette.primary),
                  ),
                )
              : Text(
                  c.displayInitials,
                  style: VfType.sectionTitle.copyWith(color: Colors.white),
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  VouchFlowStatusBadge(
                    label: statusLabel(c.status),
                    tag: companyStatusTag(c.status),
                  ),
                  Text(
                    c.plan?.name ?? 'platform.noPlan'.tr,
                    style: VfType.small.copyWith(color: t.text2),
                  ),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.faint,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: palette.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'platform.co.palette'.trParams({'name': palette.label}),
                        style: VfType.small.copyWith(color: t.text2),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                c.name,
                style: VfType.pageTitle.copyWith(color: t.text, fontSize: 24),
              ),
              if (contact.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(contact, style: VfType.small.copyWith(color: t.text2)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ChangePlanForm extends StatefulWidget {
  const _ChangePlanForm({required this.company, required this.plans});

  final PlatformCompany company;
  final List<PlatformPlan> plans;

  @override
  State<_ChangePlanForm> createState() => _ChangePlanFormState();
}

class _ChangePlanFormState extends State<_ChangePlanForm> {
  late int? _planId = widget.company.planId;
  bool _busy = false;

  Future<void> _go() async {
    final id = _planId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final message = await PlatformRepository.to.changePlan(
        widget.company.id,
        id,
      );
      showToast('platform.co.planChanged'.tr, body: message);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      showToast(
        'platform.co.couldNotChangePlan'.tr,
        body: errorText(e),
        kind: ToastKind.bad,
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        VouchFlowDropdown<int>(
          label: 'platform.plan'.tr,
          items: [for (final p in widget.plans) p.id],
          value: _planId,
          itemLabel: (id) {
            final p = widget.plans.firstWhere((x) => x.id == id);
            return '${p.name} — ${p.price > 0 ? money(p.price, p.currency) : 'platform.custom'.tr}';
          },
          onChanged: (v) => setState(() => _planId = v),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: VouchFlowButton(
                label: 'platform.cancel'.tr,
                variant: VfButtonVariant.secondary,
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: VouchFlowButton(
                label: 'platform.confirm'.tr,
                loading: _busy,
                onPressed: _busy || _planId == null ? null : _go,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusActions extends StatefulWidget {
  const _StatusActions({required this.company, required this.suspend});

  final PlatformCompany company;
  final bool suspend;

  @override
  State<_StatusActions> createState() => _StatusActionsState();
}

class _StatusActionsState extends State<_StatusActions> {
  bool _busy = false;

  Future<void> _go() async {
    final c = widget.company;
    setState(() => _busy = true);
    try {
      await PlatformRepository.to.setCompanyStatus(
        c.id,
        suspend: widget.suspend,
      );
      showToast(
        widget.suspend
            ? 'platform.companies.suspended'.tr
            : 'platform.companies.activated'.tr,
        body: c.name,
        kind: widget.suspend ? ToastKind.warn : ToastKind.ok,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      showToast(
        'platform.couldNotUpdateCompany'.tr,
        body: errorText(e),
        kind: ToastKind.bad,
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: VouchFlowButton(
            label: 'platform.cancel'.tr,
            variant: VfButtonVariant.secondary,
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: VouchFlowButton(
            label: widget.suspend
                ? 'platform.suspend'.tr
                : 'platform.activate'.tr,
            variant: widget.suspend
                ? VfButtonVariant.dangerSolid
                : VfButtonVariant.primary,
            loading: _busy,
            onPressed: _busy ? null : _go,
          ),
        ),
      ],
    );
  }
}

/// Edit branding: interface palette, the three document colours and the
/// voucher header / footer text (POST /platform/companies/{id}/branding).
class _BrandingForm extends StatefulWidget {
  const _BrandingForm({required this.company});

  final PlatformCompany company;

  @override
  State<_BrandingForm> createState() => _BrandingFormState();
}

class _BrandingFormState extends State<_BrandingForm> {
  late String _palette = widget.company.colorTheme;
  late final _colours = {
    'primary_color': TextEditingController(
      text: widget.company.primaryColor ?? '',
    ),
    'secondary_color': TextEditingController(
      text: widget.company.secondaryColor ?? '',
    ),
    'accent_color': TextEditingController(
      text: widget.company.accentColor ?? '',
    ),
  };
  late final _header = TextEditingController(
    text: widget.company.voucherHeaderText ?? '',
  );
  late final _footer = TextEditingController(
    text: widget.company.voucherFooterText ?? '',
  );
  Map<String, String> _errors = {};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [..._colours.values, _header, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      await PlatformRepository.to.saveBranding(widget.company.id, {
        'color_theme': _palette,
        for (final e in _colours.entries) e.key: e.value.text,
        'voucher_header_text': _header.text,
        'voucher_footer_text': _footer.text,
      });
      showToast('platform.co.brandingSaved'.tr, body: widget.company.name);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errors = {
          for (final x in e.errors.entries)
            x.key: x.value.isEmpty ? '' : x.value.first,
        };
      });
      if (e.errors.isEmpty) {
        showToast(
          'platform.co.couldNotSaveBranding'.tr,
          body: e.message,
          kind: ToastKind.bad,
        );
      }
    } catch (e) {
      showToast(
        'platform.co.couldNotSaveBranding'.tr,
        body: errorText(e),
        kind: ToastKind.bad,
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(String key) async {
    final ctrl = _colours[key]!;
    final picked = await showVouchFlowBottomSheet<Color>(
      context,
      title: 'platform.co.pickColour'.tr,
      child: _ColourPicker(
        initial: parseHex(ctrl.text) ?? const Color(0xFF2E3192),
      ),
    );
    if (picked != null) setState(() => ctrl.text = toHex(picked));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    const labels = {
      'primary_color': 'platform.co.primaryColour',
      'secondary_color': 'platform.co.secondaryColour',
      'accent_color': 'platform.co.accentColour',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'platform.co.interfacePalette'.tr,
          style: VfType.label.copyWith(color: t.text2),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in PlatformPalette.all)
              Semantics(
                selected: _palette == p.key,
                inMutuallyExclusiveGroup: true,
                button: true,
                child: InkWell(
                  onTap: () => setState(() => _palette = p.key),
                  borderRadius: BorderRadius.circular(VfSize.radiusL),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _palette == p.key ? t.primarySoft : t.surface,
                      borderRadius: BorderRadius.circular(VfSize.radiusL),
                      border: Border.all(
                        color: _palette == p.key ? t.primary : t.border,
                        width: _palette == p.key ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: p.primary,
                            shape: BoxShape.circle,
                          ),
                          child: _palette == p.key
                              ? const Icon(
                                  PhosphorIconsBold.check,
                                  size: 12,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          p.label,
                          style: VfType.small.copyWith(
                            color: t.text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        for (final key in _colours.keys) ...[
          VouchFlowTextField(
            label: labels[key]!.tr,
            controller: _colours[key],
            placeholder: '#1D4ED8',
            error: _errors[key],
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
              LengthLimitingTextInputFormatter(7),
            ],
            onChanged: (_) => setState(() {}),
            suffix: Padding(
              padding: const EdgeInsets.all(8),
              child: InkWell(
                onTap: () => _pick(key),
                borderRadius: BorderRadius.circular(VfSize.radiusS),
                child: Tooltip(
                  message: 'platform.co.pickColour'.tr,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: parseHex(_colours[key]!.text) ?? t.surface3,
                      borderRadius: BorderRadius.circular(VfSize.radiusS),
                      border: Border.all(color: t.borderStrong),
                    ),
                    child: parseHex(_colours[key]!.text) == null
                        ? Icon(
                            PhosphorIconsRegular.eyedropper,
                            size: 16,
                            color: t.muted,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        VouchFlowTextField(
          label: 'platform.co.headerText'.tr,
          controller: _header,
          maxLength: 255,
          error: _errors['voucher_header_text'],
        ),
        const SizedBox(height: 14),
        VouchFlowTextField(
          label: 'platform.co.footerText'.tr,
          controller: _footer,
          maxLength: 500,
          maxLines: 4,
          minLines: 3,
          error: _errors['voucher_footer_text'],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: VouchFlowButton(
                label: 'platform.cancel'.tr,
                variant: VfButtonVariant.secondary,
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: VouchFlowButton(
                label: 'platform.co.saveBranding'.tr,
                loading: _busy,
                onPressed: _busy ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A hue / saturation / brightness picker — the phone form of the web's
/// native colour input.
class _ColourPicker extends StatefulWidget {
  const _ColourPicker({required this.initial});

  final Color initial;

  @override
  State<_ColourPicker> createState() => _ColourPickerState();
}

class _ColourPickerState extends State<_ColourPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Widget _slider(
    String label,
    double value,
    double max,
    ValueChanged<double> onChanged,
    List<Color> track,
  ) {
    final t = context.vf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: VfType.label.copyWith(color: t.text2)),
        const SizedBox(height: 6),
        Container(
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VfSize.radiusPill),
            gradient: LinearGradient(colors: track),
          ),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 0,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
            ),
            child: Slider(value: value, max: max, onChanged: onChanged),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final colour = _hsv.toColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(VfSize.radiusL),
                border: Border.all(color: t.border),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              toHex(colour),
              style: VfType.sectionTitle.copyWith(
                color: t.text,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _slider(
          'platform.co.hue'.tr,
          _hsv.hue,
          360,
          (v) => setState(() => _hsv = _hsv.withHue(v)),
          [
            for (var h = 0; h <= 360; h += 60)
              HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
          ],
        ),
        _slider(
          'platform.co.saturation'.tr,
          _hsv.saturation,
          1,
          (v) => setState(() => _hsv = _hsv.withSaturation(v)),
          [_hsv.withSaturation(0).toColor(), _hsv.withSaturation(1).toColor()],
        ),
        _slider(
          'platform.co.brightness'.tr,
          _hsv.value,
          1,
          (v) => setState(() => _hsv = _hsv.withValue(v)),
          [Colors.black, _hsv.withValue(1).toColor()],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: VouchFlowButton(
                label: 'platform.cancel'.tr,
                variant: VfButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: VouchFlowButton(
                label: 'platform.co.useColour'.tr,
                onPressed: () => Navigator.of(context).pop(colour),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

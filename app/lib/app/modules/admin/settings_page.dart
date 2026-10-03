import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/dev_hooks.dart';
import '../../core/theme.dart';
import '../../data/models/admin_models.dart';
import '../../data/services/admin_repository.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import 'admin_widgets.dart';
import 'workflow_builder.dart';

/// Settings: the approval workflow (#workflow), voucher types and numbering
/// (#types) and the company profile (#company), chosen from the settings
/// chips. The workflow and the profile save from a sticky bar.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.repository});

  final AdminRepository? repository;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AdminRepository _repo = widget.repository ?? AdminRepository.to;
  final _workflowKey = GlobalKey<WorkflowBuilderState>();
  final _typesKey = GlobalKey<_VoucherTypesState>();
  final _companyKey = GlobalKey<_CompanyProfileState>();
  final _workflowSave = AdminSaveState();
  final _companySave = AdminSaveState();

  @override
  void initState() {
    super.initState();
    // Development screenshots may open a section directly (?section=types).
    final s = DevHooks.pushArgs['section'];
    if (s == 'types' || s == 'company' || s == 'workflow') {
      AdminSettings.section.value = s!;
    }
  }

  @override
  void dispose() {
    _workflowSave.dispose();
    _companySave.dispose();
    super.dispose();
  }

  Future<void> _refresh(String section) async {
    switch (section) {
      case 'types':
        await _typesKey.currentState?.load();
      case 'company':
        await _companyKey.currentState?.load();
      default:
        await _workflowKey.currentState?.reload();
    }
  }

  /// The sticky save bar for the workflow and the company profile.
  Widget _saveBar(
    AdminSaveState state,
    String label, {
    bool showDirty = false,
  }) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      if (!state.ready) return const SizedBox.shrink();
      final t = context.vf;
      return AdminSaveBar(
        leading: showDirty && state.dirty
            ? Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: t.warningStrong,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'admin.wfcUnsaved'.tr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: VfType.small.copyWith(color: t.text2),
                    ),
                  ),
                ],
              )
            : null,
        child: VouchFlowButton(
          label: label,
          icon: PhosphorIconsRegular.floppyDisk,
          expand: !showDirty || !state.dirty,
          loading: state.busy,
          onPressed: state.busy || !state.dirty ? null : state.onSave,
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final section = AdminSettings.section.value;
      final heading = switch (section) {
        'types' => 'admin.voucherSettings'.tr,
        'company' => 'admin.companyProfile'.tr,
        _ => 'admin.approvalWorkflow'.tr,
      };
      return AdminPageBody(
        key: ValueKey(section),
        route: '/settings',
        title: heading,
        onRefresh: () => _refresh(section),
        action: section == 'types'
            ? AdminRoundAction(
                icon: PhosphorIconsBold.plus,
                label: 'admin.add'.tr,
                onPressed: () => _typesKey.currentState?.openForm(),
              )
            : null,
        bottomBar: switch (section) {
          'types' => null,
          'company' => _saveBar(_companySave, 'admin.saveChanges'.tr),
          _ => _saveBar(
            _workflowSave,
            'admin.saveWorkflow'.tr,
            showDirty: true,
          ),
        },
        children: [
          switch (section) {
            'types' => _VoucherTypes(key: _typesKey, repo: _repo),
            'company' => _CompanyProfile(
              key: _companyKey,
              repo: _repo,
              save: _companySave,
            ),
            _ => WorkflowBuilder(
              key: _workflowKey,
              repository: _repo,
              saveState: _workflowSave,
            ),
          },
        ],
      );
    });
  }
}

/* ──────────────────────────────────────────────── voucher types ─────────── */

class _VoucherTypes extends StatefulWidget {
  const _VoucherTypes({super.key, required this.repo});
  final AdminRepository repo;

  @override
  State<_VoucherTypes> createState() => _VoucherTypesState();
}

class _VoucherTypesState extends State<_VoucherTypes> {
  List<AdminVoucherType>? _types;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final types = await widget.repo.voucherTypes(includeInactive: true);
      if (mounted) setState(() => _types = types);
    } catch (_) {
      // As on the web: a failed load reads as an empty list.
      if (mounted) setState(() => _types = const []);
    }
  }

  Future<void> openForm([AdminVoucherType? editing]) async {
    final saved = await showAdminSheet<bool>(
      context,
      (ctx, _) => _VoucherTypeForm(repo: widget.repo, editing: editing),
    );
    if (saved == true) load();
  }

  @override
  Widget build(BuildContext context) {
    final types = _types;
    if (types == null) {
      return const VouchFlowLoadingState(rows: 4, rowHeight: 72);
    }
    final locale = Get.locale?.languageCode ?? 'en';
    if (types.isEmpty) {
      return VouchFlowCard(
        radius: VfSize.radiusXl,
        child: VouchFlowEmptyState(
          icon: PhosphorIconsRegular.receipt,
          title: 'admin.noResults'.tr,
          actionLabel: 'admin.add'.tr,
          onAction: () => openForm(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in types)
          AdminListRow(
            semanticLabel: '${'admin.edit'.tr} ${type.name}',
            leading: AdminIconTile(
              PhosphorIconsRegular.receipt,
              tone: type.isActive ? VfTone.primary : VfTone.neutral,
            ),
            title: type.label(locale),
            meta: [
              if (type.nextNumberPreview.isNotEmpty)
                type.nextNumberPreview
              else
                type.prefix,
              '${type.vouchersCount} ${'admin.vouchers'.tr.toLowerCase()}',
            ].join(' · '),
            trailing: type.isActive
                ? const AdminChevron()
                : AdminBadge('admin.inactive'.tr),
            onTap: () => openForm(type),
          ),
      ],
    );
  }
}

class _VoucherTypeForm extends StatefulWidget {
  const _VoucherTypeForm({required this.repo, required this.editing});
  final AdminRepository repo;
  final AdminVoucherType? editing;

  @override
  State<_VoucherTypeForm> createState() => _VoucherTypeFormState();
}

class _VoucherTypeFormState extends State<_VoucherTypeForm> {
  late final AdminVoucherType? e = widget.editing;
  late final _name = TextEditingController(text: e?.name ?? '');
  late final _nameSw = TextEditingController(text: e?.nameSw ?? '');
  late final _code = TextEditingController(text: e?.code ?? '');
  late final _prefix = TextEditingController(text: e?.prefix ?? '');
  late final _pad = TextEditingController(text: '${e?.seqPadding ?? 6}');
  late final _next = TextEditingController(text: '${e?.nextNumber ?? 1}');
  late bool _reset = e?.resetYearly ?? true;
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _code, _prefix]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _nameSw, _code, _prefix, _pad, _next]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.saveVoucherType(e?.id, {
        'name': _name.text,
        'name_sw': _nameSw.text,
        'code': _code.text,
        'prefix': _prefix.text,
        'seq_padding': int.tryParse(_pad.text) ?? 0,
        'next_number': int.tryParse(_next.text) ?? 0,
        'reset_yearly': _reset,
      });
      showToast(
        e != null ? 'admin.vtUpdated'.tr : 'admin.vtCreated'.tr,
        body: _name.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      if (err is ApiException && mounted) setState(() => _error = err);
      adminReport(err, 'admin.couldNotSaveVt'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    final ready =
        _name.text.isNotEmpty &&
        _code.text.isNotEmpty &&
        _prefix.text.isNotEmpty;
    return VouchFlowDialog(
      title: e != null ? 'admin.edit'.tr : 'admin.add'.tr,
      icon: PhosphorIconsRegular.receipt,
      tone: VfTone.primary,
      actions: [
        VouchFlowButton(
          label: 'admin.cancel'.tr,
          variant: VfButtonVariant.secondary,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        VouchFlowButton(
          label: 'admin.save'.tr,
          loading: _busy,
          onPressed: _busy || !ready ? null : _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VouchFlowTextField(
            label: 'admin.wfcNameEn'.tr,
            controller: _name,
            required: true,
            error: _error?.field('name'),
          ),
          gap,
          VouchFlowTextField(
            label: 'admin.wfcNameSw'.tr,
            controller: _nameSw,
            error: _error?.field('name_sw'),
          ),
          gap,
          VouchFlowTextField(
            label: 'admin.code'.tr,
            controller: _code,
            required: true,
            error: _error?.field('code'),
          ),
          gap,
          VouchFlowTextField(
            label: 'admin.vtPrefix'.tr,
            controller: _prefix,
            required: true,
            hint: 'admin.vtPrefixHint'.tr,
            error: _error?.field('prefix'),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [_UpperCase()],
          ),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: VouchFlowTextField(
                  label: 'admin.vtDigits'.tr,
                  controller: _pad,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  error: _error?.field('seq_padding'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: VouchFlowTextField(
                  label: 'admin.vtNextNumber'.tr,
                  controller: _next,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  error: _error?.field('next_number'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          AdminCheck(
            label: 'admin.vtResetYearly'.tr,
            value: _reset,
            onChanged: (v) => setState(() => _reset = v),
          ),
        ],
      ),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

/* ─────────────────────────────────────────────── company profile ────────── */

class _CompanyProfile extends StatefulWidget {
  const _CompanyProfile({super.key, required this.repo, required this.save});
  final AdminRepository repo;

  /// The page's sticky save bar.
  final AdminSaveState save;

  @override
  State<_CompanyProfile> createState() => _CompanyProfileState();
}

class _CompanyProfileState extends State<_CompanyProfile> {
  final _name = TextEditingController();
  final _legal = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();
  String _currency = 'TZS', _locale = 'en';
  String? _timezone;
  CompanyProfile? _company;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.save.update(ready: false, busy: false, dirty: true, onSave: _save);
    load();
  }

  @override
  void dispose() {
    widget.save.update(ready: false);
    for (final c in [_name, _legal, _email, _phone, _website, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    setState(() => _error = null);
    try {
      final c = await widget.repo.company();
      if (!mounted) return;
      setState(() {
        _company = c;
        _name.text = c.name;
        _legal.text = c.legalName ?? '';
        _email.text = c.email;
        _phone.text = c.phone ?? '';
        _website.text = c.website ?? '';
        _address.text = c.address ?? '';
        _currency = c.currency;
        _locale = c.locale;
        _timezone = c.timezone;
      });
      widget.save.update(ready: true);
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorText(e));
    }
  }

  Future<void> _save() async {
    // Nothing is sent before the profile has loaded into the fields.
    if (_company == null || _busy) return;
    setState(() => _busy = true);
    widget.save.update(busy: true);
    try {
      await widget.repo.updateCompany({
        'name': _name.text,
        'legal_name': _legal.text,
        'email': _email.text,
        'phone': _phone.text,
        'address': _address.text,
        'website': _website.text,
        'currency': _currency,
        'locale': _locale,
        'timezone': ?_timezone,
      });
      if (Get.isRegistered<SessionService>()) {
        await Get.find<SessionService>().refresh();
      }
      showToast('admin.companyUpdated'.tr, body: _name.text);
      await load();
    } catch (e) {
      adminReport(e, 'admin.couldNotSaveCompany'.tr);
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.save.update(busy: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return VouchFlowErrorState(
        message: _error!,
        onRetry: load,
        retryLabel: 'action.retry'.tr,
      );
    }
    if (_company == null) {
      return const VouchFlowLoadingState(rows: 3, rowHeight: 150);
    }
    const currencies = ['TZS', 'KES', 'USD', 'EUR'];
    const gap = SizedBox(height: 22);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSection(
          label: 'admin.companyDetails'.tr,
          child: AdminFields([
            VouchFlowTextField(
              label: 'admin.companyName'.tr,
              controller: _name,
              required: true,
              prefixIcon: PhosphorIconsRegular.buildings,
            ),
            VouchFlowTextField(
              label: 'admin.legalNamePlain'.tr,
              controller: _legal,
            ),
          ]),
        ),
        gap,
        AdminSection(
          label: 'admin.contact'.tr,
          child: AdminFields([
            VouchFlowTextField(
              label: 'admin.businessEmail'.tr,
              controller: _email,
              required: true,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: PhosphorIconsRegular.envelopeSimple,
            ),
            VouchFlowTextField(
              label: 'admin.phone'.tr,
              controller: _phone,
              keyboardType: TextInputType.phone,
              prefixIcon: PhosphorIconsRegular.phone,
            ),
            VouchFlowTextField(
              label: 'admin.website'.tr,
              controller: _website,
              keyboardType: TextInputType.url,
              prefixIcon: PhosphorIconsRegular.globe,
            ),
            VouchFlowTextField(
              label: 'admin.address'.tr,
              controller: _address,
              prefixIcon: PhosphorIconsRegular.mapPin,
            ),
          ]),
        ),
        gap,
        AdminSection(
          label: 'admin.regional'.tr,
          child: AdminFields([
            VouchFlowDropdown<String>(
              label: 'admin.currency'.tr,
              items: [
                ...currencies,
                if (!currencies.contains(_currency)) _currency,
              ],
              value: _currency,
              itemLabel: (v) => v,
              onChanged: (v) => setState(() => _currency = v ?? _currency),
            ),
            VouchFlowDropdown<String>(
              label: 'admin.language'.tr,
              items: const ['en', 'sw'],
              value: _locale,
              itemLabel: (v) => v == 'sw' ? 'Kiswahili' : 'English',
              onChanged: (v) => setState(() => _locale = v ?? _locale),
            ),
          ]),
        ),
      ],
    );
  }
}

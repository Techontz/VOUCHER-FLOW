import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/platform_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/platform_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import 'platform_widgets.dart';

/// Every tenant on the platform (web: /platform/companies) — search, status
/// filter, a card per company, the row actions (view, suspend / activate,
/// delete) and the New company dialog.
class PlatformCompaniesPage extends StatefulWidget {
  const PlatformCompaniesPage({super.key});

  @override
  State<PlatformCompaniesPage> createState() => _PlatformCompaniesPageState();
}

class _PlatformCompaniesPageState extends State<PlatformCompaniesPage> {
  final _repo = PlatformRepository.to;
  String _q = '';
  String _status = '';
  int _page = 1;
  PlatformPage<PlatformCompany>? _result;
  String? _error;
  List<PlatformPlan> _plans = const [];
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
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
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _error = null);
    try {
      final r = await _repo.companies(q: _q, status: _status, page: _page);
      if (mounted && seq == _seq) setState(() => _result = r);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = errorText(e));
    }
  }

  void _search(String v) {
    _q = v;
    _page = 1;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _load);
  }

  Future<void> _openCreate() async {
    final created = await showVouchFlowDialog<bool>(
      context,
      dismissible: false,
      dialog: VouchFlowDialog(
        icon: PhosphorIconsRegular.buildings,
        title: 'platform.companies.new'.tr,
        subtitle: 'platform.create.sub'.tr,
        child: _CreateCompanyForm(plans: _plans),
      ),
    );
    if (created == true) _load();
  }

  Future<void> _openActions(PlatformCompany c) async {
    final t = context.vf;
    final suspended = c.status == 'suspended';
    final action = await showVouchFlowBottomSheet<String>(
      context,
      title: c.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionTile(
            icon: PhosphorIconsRegular.arrowSquareOut,
            label: 'platform.companies.viewDetails'.tr,
            value: 'view',
          ),
          suspended
              ? _ActionTile(
                  icon: PhosphorIconsRegular.checkCircle,
                  label: 'platform.activate'.tr,
                  value: 'activate',
                )
              : _ActionTile(
                  icon: PhosphorIconsRegular.prohibit,
                  label: 'platform.suspend'.tr,
                  value: 'suspend',
                ),
          Divider(color: t.border, height: 1),
          _ActionTile(
            icon: PhosphorIconsRegular.trash,
            label: 'platform.companies.delete'.tr,
            value: 'delete',
            danger: true,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'view') {
      _openCompany(c);
    } else {
      _confirm(action, c);
    }
  }

  Future<void> _openCompany(PlatformCompany c) async {
    await Get.toNamed(Routes.platformCompany, arguments: c.id);
    if (mounted) _load();
  }

  Future<void> _confirm(String kind, PlatformCompany c) async {
    final done = await showVouchFlowDialog<bool>(
      context,
      dialog: VouchFlowDialog(
        icon: kind == 'delete'
            ? PhosphorIconsRegular.trash
            : kind == 'suspend'
            ? PhosphorIconsRegular.prohibit
            : PhosphorIconsRegular.checkCircle,
        tone: kind == 'activate'
            ? VfTone.ok
            : (kind == 'suspend' ? VfTone.warn : VfTone.bad),
        title: 'platform.confirm.${kind}Title'.tr,
        subtitle: 'platform.confirm.${kind}Sub'.tr,
        summary: [
          VfSummaryRow('platform.companyName'.tr, c.name),
          VfSummaryRow('platform.users'.tr, '${c.usersCount}'),
          VfSummaryRow('platform.vouchers'.tr, '${c.vouchersCount}'),
        ],
        child: _PendingActions(kind: kind, company: c),
      ),
    );
    if (done == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final rows = _result?.items ?? const <PlatformCompany>[];
    return VouchFlowPageBody(
      onRefresh: _load,
      children: [
        VouchFlowPageHeader(
          kicker: 'platform.kicker'.tr,
          title: 'platform.companies.title'.tr,
          subtitle: 'platform.companies.sub'.tr,
        ),
        const SizedBox(height: 14),
        VouchFlowButton(
          label: 'platform.companies.new'.tr,
          icon: PhosphorIconsRegular.plus,
          expand: true,
          onPressed: _openCreate,
        ),
        const SizedBox(height: 16),
        VouchFlowCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    VouchFlowSearchField(
                      placeholder: 'platform.search'.tr,
                      onChanged: _search,
                    ),
                    const SizedBox(height: 10),
                    PlatformSelect<String>(
                      semanticLabel: 'platform.status'.tr,
                      value: _status,
                      items: [
                        ('', 'platform.allStatuses'.tr),
                        for (final s in const [
                          'active',
                          'trial',
                          'past_due',
                          'suspended',
                        ])
                          (s, statusLabel(s)),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _status = v;
                          _page = 1;
                        });
                        _load();
                      },
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: t.border),
              if (_error != null || _result == null)
                platformPanelState(
                  loading: _result == null,
                  error: _error,
                  onRetry: _load,
                  rows: 5,
                )
              else if (rows.isEmpty)
                VouchFlowEmptyState(
                  icon: PhosphorIconsRegular.buildings,
                  title: 'platform.noResults'.tr,
                  actionLabel: 'platform.companies.new'.tr,
                  onAction: _openCreate,
                )
              else ...[
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: t.border),
                  _CompanyRow(
                    company: rows[i],
                    onOpen: () => _openCompany(rows[i]),
                    onMore: () => _openActions(rows[i]),
                  ),
                ],
                if ((_result?.lastPage ?? 1) > 1)
                  Divider(height: 1, color: t.border),
                PlatformPager(
                  page: _result!.page,
                  lastPage: _result!.lastPage,
                  total: _result!.total,
                  onChanged: (p) {
                    setState(() => _page = p);
                    _load();
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CompanyRow extends StatelessWidget {
  const _CompanyRow({
    required this.company,
    required this.onOpen,
    required this.onMore,
  });

  final PlatformCompany company;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = company;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: VfType.bodyStrong.copyWith(color: t.primaryText),
                  ),
                  if (c.email != null)
                    Text(
                      c.email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VfType.small.copyWith(color: t.muted),
                    ),
                  const SizedBox(height: 8),
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
                        c.plan?.name ?? '—',
                        style: VfType.small.copyWith(
                          color: t.text2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      _Fact(
                        label: 'platform.users'.tr,
                        value: '${c.usersCount}',
                      ),
                      _Fact(
                        label: 'platform.vouchers'.tr,
                        value: '${c.vouchersCount}',
                      ),
                      _Fact(
                        label: 'platform.renews'.tr,
                        value: Fmt.date(c.renewsAt),
                      ),
                      _Fact(
                        label: 'platform.joined'.tr,
                        value: Fmt.date(c.createdAt),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            VouchFlowIconButton(
              icon: PhosphorIconsRegular.dotsThreeOutline,
              tooltip: '${'platform.actions'.tr} · ${c.name}',
              onPressed: onMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(color: t.muted),
          ),
          TextSpan(
            text: value,
            style: TextStyle(color: t.text, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      style: VfType.small.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.value,
    this.danger = false,
  });

  final IconData icon;
  final String label, value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final colour = danger ? t.dangerStrong : t.text;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 52,
      leading: Icon(icon, color: danger ? t.dangerStrong : t.text2, size: 20),
      title: Text(
        label,
        style: VfType.body.copyWith(color: colour, fontWeight: FontWeight.w500),
      ),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

/// Suspend / activate / delete: the confirm dialog's actions (and, for a
/// delete, the type-the-name field), with the call made from here.
class _PendingActions extends StatefulWidget {
  const _PendingActions({required this.kind, required this.company});

  final String kind;
  final PlatformCompany company;

  @override
  State<_PendingActions> createState() => _PendingActionsState();
}

class _PendingActionsState extends State<_PendingActions> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final repo = PlatformRepository.to;
    final c = widget.company;
    setState(() => _busy = true);
    try {
      if (widget.kind == 'delete') {
        await repo.deleteCompany(c.id);
        showToast(
          'platform.companies.deleted'.tr,
          body: c.name,
          kind: ToastKind.warn,
        );
      } else {
        final suspend = widget.kind == 'suspend';
        await repo.setCompanyStatus(c.id, suspend: suspend);
        showToast(
          suspend
              ? 'platform.companies.suspended'.tr
              : 'platform.companies.activated'.tr,
          body: c.name,
          kind: suspend ? ToastKind.warn : ToastKind.ok,
        );
      }
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
    final kind = widget.kind;
    final c = widget.company;
    final canGo = kind != 'delete' || _name.text.trim() == c.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kind == 'delete') ...[
          VouchFlowTextField(
            label: 'platform.confirm.typeName'.trParams({'name': c.name}),
            controller: _name,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 16),
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
                label: kind == 'delete'
                    ? 'platform.companies.delete'.tr
                    : kind == 'suspend'
                    ? 'platform.suspend'.tr
                    : 'platform.activate'.tr,
                variant: kind == 'activate'
                    ? VfButtonVariant.primary
                    : VfButtonVariant.dangerSolid,
                loading: _busy,
                onPressed: _busy || !canGo ? null : _go,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The New company form: the company, its plan, and its first administrator.
class _CreateCompanyForm extends StatefulWidget {
  const _CreateCompanyForm({required this.plans});

  final List<PlatformPlan> plans;

  @override
  State<_CreateCompanyForm> createState() => _CreateCompanyFormState();
}

class _CreateCompanyFormState extends State<_CreateCompanyForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _adminName = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminTitle = TextEditingController();
  final _adminPassword = TextEditingController();
  int? _planId;
  Map<String, String> _errors = {};
  String? _formError;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _email,
      _phone,
      _adminName,
      _adminEmail,
      _adminTitle,
      _adminPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canCreate =>
      _name.text.trim().isNotEmpty &&
      _email.text.trim().isNotEmpty &&
      _adminName.text.trim().isNotEmpty &&
      _adminEmail.text.trim().isNotEmpty &&
      _adminPassword.text.length >= 8;

  String? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _errors = {};
      _formError = null;
    });
    try {
      final name = await PlatformRepository.to.createCompany(
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _opt(_phone),
        planId: _planId,
        adminName: _adminName.text.trim(),
        adminEmail: _adminEmail.text.trim(),
        adminJobTitle: _opt(_adminTitle),
        adminPassword: _adminPassword.text,
      );
      showToast(
        'platform.companies.created'.tr,
        body: 'platform.companies.createdBody'.trParams({
          'name': name,
          'email': _adminEmail.text.trim(),
        }),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.errors.isNotEmpty) {
          _errors = {
            for (final x in e.errors.entries)
              x.key: x.value.isEmpty ? '' : x.value.first,
          };
        } else {
          _formError = e.message.isEmpty
              ? 'platform.companies.couldNotCreate'.tr
              : e.message;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _formError = 'platform.companies.couldNotCreate'.tr;
        });
      }
    }
  }

  Widget _gap() => const SizedBox(height: 14);

  @override
  Widget build(BuildContext context) {
    void touch(String _) => setState(() {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_formError != null) ...[
          VouchFlowAlert(
            message: _formError!,
            tone: VfTone.bad,
            icon: PhosphorIconsRegular.warningCircle,
          ),
          _gap(),
        ],
        VouchFlowEyebrow('platform.create.company'.tr),
        const SizedBox(height: 10),
        VouchFlowTextField(
          label: 'platform.companyName'.tr,
          required: true,
          controller: _name,
          placeholder: 'Kilimanjaro Logistics Ltd',
          error: _errors['company.name'],
          onChanged: touch,
          textCapitalization: TextCapitalization.words,
        ),
        _gap(),
        VouchFlowTextField(
          label: 'platform.create.companyEmail'.tr,
          required: true,
          controller: _email,
          placeholder: 'finance@company.co.tz',
          keyboardType: TextInputType.emailAddress,
          error: _errors['company.email'],
          onChanged: touch,
        ),
        _gap(),
        VouchFlowTextField(
          label: 'platform.create.phone'.tr,
          controller: _phone,
          placeholder: '+255 7…',
          keyboardType: TextInputType.phone,
          error: _errors['company.phone'],
        ),
        _gap(),
        VouchFlowDropdown<int?>(
          label: 'platform.plan'.tr,
          hint: 'platform.create.planHint'.tr,
          error: _errors['plan_id'],
          items: [null, ...widget.plans.map((p) => p.id)],
          value: _planId,
          itemLabel: (id) {
            if (id == null) return 'platform.create.defaultPlan'.tr;
            final p = widget.plans.firstWhere((x) => x.id == id);
            return p.trialDays > 0
                ? '${p.name} · ${'platform.create.dayTrial'.trParams({'n': '${p.trialDays}'})}'
                : p.name;
          },
          onChanged: (v) => setState(() => _planId = v),
        ),
        const SizedBox(height: 22),
        VouchFlowEyebrow('platform.create.firstAdmin'.tr),
        const SizedBox(height: 10),
        VouchFlowTextField(
          label: 'platform.create.fullName'.tr,
          required: true,
          controller: _adminName,
          error: _errors['admin.name'],
          onChanged: touch,
          textCapitalization: TextCapitalization.words,
        ),
        _gap(),
        VouchFlowTextField(
          label: 'platform.create.jobTitle'.tr,
          controller: _adminTitle,
          placeholder: 'Company Administrator',
          error: _errors['admin.job_title'],
        ),
        _gap(),
        VouchFlowTextField(
          label: 'platform.create.signInEmail'.tr,
          required: true,
          controller: _adminEmail,
          keyboardType: TextInputType.emailAddress,
          error: _errors['admin.email'],
          onChanged: touch,
        ),
        _gap(),
        VouchFlowTextField(
          label: 'platform.create.password'.tr,
          required: true,
          controller: _adminPassword,
          obscure: true,
          hint: 'platform.create.passwordHint'.tr,
          error: _errors['admin.password'],
          onChanged: touch,
          autofillHints: const [AutofillHints.newPassword],
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
                label: _busy
                    ? 'platform.create.creating'.tr
                    : 'platform.create.submit'.tr,
                icon: PhosphorIconsRegular.plus,
                loading: _busy,
                onPressed: _busy || !_canCreate ? null : _create,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/platform_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/platform_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import 'platform_widgets.dart';

/// Plans & subscriptions (web: /platform/plans): every plan with its price,
/// cycle, limits, companies on it and status; add and edit.
class PlatformPlansPage extends StatefulWidget {
  const PlatformPlansPage({super.key});

  @override
  State<PlatformPlansPage> createState() => _PlatformPlansPageState();
}

class _PlatformPlansPageState extends State<PlatformPlansPage> {
  List<PlatformPlan>? _plans;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await PlatformRepository.to.plans();
      if (mounted) setState(() => _plans = p);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _open([PlatformPlan? plan]) async {
    final saved = await showVouchFlowDialog<bool>(
      context,
      dismissible: false,
      dialog: VouchFlowDialog(
        title: plan == null
            ? 'platform.add'.tr
            : '${'platform.edit'.tr} — ${plan.name}',
        child: _PlanForm(plan: plan),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    return VouchFlowPageBody(
      onRefresh: _load,
      children: [
        VouchFlowPageHeader(
          kicker: 'platform.kicker'.tr,
          title: 'platform.plans.title'.tr,
          subtitle: 'platform.plans.sub'.tr,
          actions: [
            VouchFlowButton(
              label: 'platform.add'.tr,
              icon: PhosphorIconsRegular.plus,
              onPressed: () => _open(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null)
          VouchFlowErrorState(
            message: _error!,
            onRetry: _load,
            retryLabel: 'action.retry'.tr,
          )
        else if (plans == null)
          const VouchFlowLoadingState(rows: 4, rowHeight: 150)
        else if (plans.isEmpty)
          VouchFlowCard(
            child: VouchFlowEmptyState(
              icon: PhosphorIconsRegular.crownSimple,
              title: 'platform.plans.empty'.tr,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 720 ? 2 : 1;
              final w = (c.maxWidth - VfSize.gap * (cols - 1)) / cols;
              return Wrap(
                spacing: VfSize.gap,
                runSpacing: VfSize.gap,
                children: [
                  for (final p in plans)
                    SizedBox(
                      width: w,
                      child: _PlanCard(plan: p, onEdit: () => _open(p)),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onEdit});

  final PlatformPlan plan;
  final VoidCallback onEdit;

  String _lim(int? v) => v == null ? '∞' : '$v';

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final p = plan;
    return VouchFlowCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: VfType.cardTitle.copyWith(color: t.text),
                    ),
                    Text(p.code, style: VfType.meta.copyWith(color: t.muted)),
                  ],
                ),
              ),
              VouchFlowStatusBadge(
                label: p.isActive
                    ? 'platform.st.active'.tr
                    : 'platform.st.inactive'.tr,
                tag: p.isActive ? 'tag-accent' : 'tag-neutral',
              ),
              VouchFlowIconButton(
                icon: PhosphorIconsRegular.pencilSimple,
                tooltip: '${'platform.edit'.tr} ${p.name}',
                onPressed: onEdit,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                Text(
                  p.price > 0
                      ? money(p.price, p.currency)
                      : 'platform.custom'.tr,
                  style: VfType.figureS.copyWith(
                    color: t.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    p.billingCycle == 'annual'
                        ? 'platform.plans.annual'.tr
                        : 'platform.plans.monthly'.tr,
                    style: VfType.small.copyWith(color: t.muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              children: [
                PlatformMetaLine(
                  label: 'platform.plans.users'.tr,
                  value: _lim(p.maxUsers),
                ),
                PlatformMetaLine(
                  label: 'platform.plans.vouchersMo'.tr,
                  value: _lim(p.maxVouchersPerMonth),
                ),
                PlatformMetaLine(
                  label: 'platform.plans.levels'.tr,
                  value: _lim(p.maxApprovalLevels),
                ),
                PlatformMetaLine(
                  label: 'platform.plans.storage'.tr,
                  value: p.storageMb != null && p.storageMb! > 0
                      ? '${p.storageMb} MB'
                      : '∞',
                ),
                PlatformMetaLine(
                  label: 'platform.plans.companies'.tr,
                  value: '${p.companiesCount}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanForm extends StatefulWidget {
  const _PlanForm({this.plan});

  final PlatformPlan? plan;

  @override
  State<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends State<_PlanForm> {
  late final PlatformPlan? p = widget.plan;
  late final _name = TextEditingController(text: p?.name ?? '');
  late final _code = TextEditingController(text: p?.code ?? '');
  late final _blurb = TextEditingController(text: p?.blurb ?? '');
  late final _price = TextEditingController(
    text: p == null ? '0' : _n(p!.price),
  );
  late final _trial = TextEditingController(text: '${p?.trialDays ?? 14}');
  late final _users = TextEditingController(
    text: p?.maxUsers?.toString() ?? '',
  );
  late final _vouchers = TextEditingController(
    text: p?.maxVouchersPerMonth?.toString() ?? '',
  );
  late final _depts = TextEditingController(
    text: p?.maxDepartments?.toString() ?? '',
  );
  late final _levels = TextEditingController(
    text: p?.maxApprovalLevels?.toString() ?? '',
  );
  late final _storage = TextEditingController(
    text: p?.storageMb?.toString() ?? '',
  );
  late String _currency = p?.currency ?? 'TZS';
  late String _cycle = p?.billingCycle ?? 'monthly';
  late bool _active = p?.isActive ?? true;
  late bool _public = p?.isPublic ?? true;
  bool _busy = false;
  ApiException? _formError;

  static String _n(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    for (final c in [
      _name,
      _code,
      _blurb,
      _price,
      _trial,
      _users,
      _vouchers,
      _depts,
      _levels,
      _storage,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _nullable(TextEditingController c) =>
      c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _formError = null;
    });
    final payload = <String, dynamic>{
      'code': _code.text.trim(),
      'name': _name.text.trim(),
      'blurb': _blurb.text.trim(),
      'price': num.tryParse(_price.text.trim()) ?? 0,
      'currency': _currency,
      'billing_cycle': _cycle,
      'max_users': _nullable(_users),
      'max_vouchers_per_month': _nullable(_vouchers),
      'max_departments': _nullable(_depts),
      'max_approval_levels': _nullable(_levels),
      'storage_mb': _nullable(_storage),
      'trial_days': int.tryParse(_trial.text.trim()) ?? 0,
      'is_active': _active,
      'is_public': _public,
      'sort_order': p?.sortOrder ?? 0,
    };
    try {
      await PlatformRepository.to.savePlan(p?.id, payload);
      showToast(
        p != null ? 'platform.plans.updated'.tr : 'platform.plans.created'.tr,
        body: _name.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (e is ApiException && mounted) setState(() => _formError = e);
      showToast(
        'platform.plans.couldNotSave'.tr,
        body: errorText(e),
        kind: ToastKind.bad,
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _num(
    String label,
    TextEditingController c, {
    String? placeholder,
    bool required = false,
    String? field,
  }) => VouchFlowTextField(
    label: label,
    controller: c,
    required: required,
    placeholder: placeholder,
    keyboardType: const TextInputType.numberWithOptions(decimal: false),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    error: field == null ? null : _formError?.field(field),
  );

  /// Two fields side by side when there is room, stacked on a narrow phone.
  Widget _pair(Widget a, Widget b) => LayoutBuilder(
    builder: (context, c) => c.maxWidth < 320
        ? Column(children: [a, const SizedBox(height: 14), b])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          ),
  );

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    const gap = SizedBox(height: 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _pair(
          VouchFlowTextField(
            label: 'platform.plans.name'.tr,
            required: true,
            controller: _name,
            error: _formError?.field('name'),
            onChanged: (_) => setState(() {}),
          ),
          VouchFlowTextField(
            label: 'platform.plans.code'.tr,
            required: true,
            controller: _code,
            error: _formError?.field('code'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        gap,
        VouchFlowTextField(
          label: 'platform.plans.blurb'.tr,
          controller: _blurb,
          error: _formError?.field('blurb'),
        ),
        gap,
        _pair(
          _num(
            'platform.plans.price'.tr,
            _price,
            required: true,
            field: 'price',
          ),
          VouchFlowDropdown<String>(
            label: 'platform.plans.currency'.tr,
            items: const ['TZS', 'KES', 'USD', 'EUR'],
            value: _currency,
            itemLabel: (v) => v,
            onChanged: (v) => setState(() => _currency = v ?? _currency),
          ),
        ),
        gap,
        _pair(
          VouchFlowDropdown<String>(
            label: 'platform.plans.cycle'.tr,
            items: const ['monthly', 'annual'],
            value: _cycle,
            itemLabel: (v) => v == 'annual'
                ? 'platform.plans.annual'.tr
                : 'platform.plans.monthly'.tr,
            onChanged: (v) => setState(() => _cycle = v ?? _cycle),
          ),
          _num('platform.plans.trialDays'.tr, _trial, field: 'trial_days'),
        ),
        const SizedBox(height: 20),
        VouchFlowEyebrow('platform.plans.limits'.tr),
        const SizedBox(height: 10),
        _pair(
          _num(
            'platform.plans.maxUsers'.tr,
            _users,
            placeholder: '∞',
            field: 'max_users',
          ),
          _num(
            'platform.plans.vouchersMonth'.tr,
            _vouchers,
            placeholder: '∞',
            field: 'max_vouchers_per_month',
          ),
        ),
        gap,
        _pair(
          _num(
            'platform.plans.departments'.tr,
            _depts,
            placeholder: '∞',
            field: 'max_departments',
          ),
          _num(
            'platform.plans.approvalLevels'.tr,
            _levels,
            placeholder: '∞',
            field: 'max_approval_levels',
          ),
        ),
        gap,
        _num(
          'platform.plans.storageMb'.tr,
          _storage,
          placeholder: '∞',
          field: 'storage_mb',
        ),
        const SizedBox(height: 10),
        _check(
          'platform.plans.active'.tr,
          _active,
          (v) => setState(() => _active = v),
          t,
        ),
        _check(
          'platform.plans.public'.tr,
          _public,
          (v) => setState(() => _public = v),
          t,
        ),
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
                label: 'platform.save'.tr,
                loading: _busy,
                onPressed:
                    _busy ||
                        _name.text.trim().isEmpty ||
                        _code.text.trim().isEmpty
                    ? null
                    : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _check(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
    VfTokens t,
  ) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(VfSize.radiusM),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: t.primary,
          ),
          Expanded(
            child: Text(label, style: VfType.body.copyWith(color: t.text)),
          ),
        ],
      ),
    ),
  );
}

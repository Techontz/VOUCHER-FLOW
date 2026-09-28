import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/auth_repository.dart';
import '../../data/services/session_service.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import 'auth_widgets.dart';
import 'brand_inputs.dart';

enum ObStep { company, logo, departments, workflow, people, plan }

class _Invite {
  _Invite({String role = 'hod'}) : role = role.obs;
  final name = TextEditingController();
  final email = TextEditingController();
  final RxString role;

  void dispose() {
    name.dispose();
    email.dispose();
  }
}

const _roles = [
  'employee',
  'hod',
  'ceo',
  'cashier',
  'finance',
  'company_admin',
];
const _swatches = ['#0088B0', '#D6006C', '#1F6F4A', '#8A4B12'];

/// The web's /onboarding: six short steps after a company is created —
/// details, logo and colour, departments, the approval workflow, the team,
/// and the plan. Each step is saved when Next is pressed; Skip setup goes
/// straight to the dashboard.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _repo = AuthRepository.to;
  final _session = Get.find<SessionService>();
  final _scroll = ScrollController();

  int _index = 0;
  bool _busy = false;

  final _address = TextEditingController();
  final _website = TextEditingController();
  final _phone = TextEditingController();
  final _colour = TextEditingController(text: '#0088B0');
  PickedLogo? _logo;
  String? _logoError;
  final _departments = <String>['Finance', 'Operations', 'Procurement'];
  final _newDept = TextEditingController();
  String _preset = 'default';
  List<WorkflowPreset> _presets = const [];
  final _invites = <_Invite>[_Invite()];
  List<Plan> _plans = const [];
  int? _planId;

  static const _steps = ObStep.values;
  ObStep get _step => _steps[_index];

  @override
  void initState() {
    super.initState();
    if (!_session.isSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Get.offAllNamed(Routes.login),
      );
      return;
    }
    final company = _session.company.value;
    _address.text = company?.address ?? '';
    _website.text = company?.website ?? '';
    _phone.text = company?.phone ?? '';
    _colour.text = (company?.primaryColor ?? '#0088b0').toUpperCase();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final presets = await _repo.workflowPresets();
      if (mounted) setState(() => _presets = presets);
    } catch (_) {
      // As on the web: the step simply offers nothing to choose.
    }
    try {
      final plans = await _repo.plans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _planId =
            _session.company.value?.plan?.id ??
            plans.firstWhereOrNull((p) => p.code == 'business')?.id;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in [_address, _website, _phone, _colour, _newDept]) {
      c.dispose();
    }
    for (final i in _invites) {
      i.dispose();
    }
    super.dispose();
  }

  void _report(Object err) {
    final fallback = 'auth.ob.saveFailed'.tr;
    if (err is ApiException) {
      final first = err.errors.values.firstOrNull?.firstOrNull;
      showToast(
        err.message.isEmpty ? fallback : err.message,
        body: first != null && first != err.message ? first : null,
        kind: ToastKind.bad,
      );
    } else {
      showToast(fallback, body: 'state.offline'.tr, kind: ToastKind.bad);
    }
  }

  Future<bool> _persist() async {
    try {
      switch (_step) {
        case ObStep.company:
          await _repo.updateCompany({
            'address': _address.text,
            'website': _website.text,
            'phone': _phone.text,
          });
        case ObStep.logo:
          await _repo.updateBranding(primaryColor: _colour.text, logo: _logo);
        case ObStep.departments:
          final have = (await _repo.departmentNames())
              .map((n) => n.toLowerCase())
              .toSet();
          for (final name in _departments) {
            final n = name.trim();
            if (n.isNotEmpty && !have.contains(n.toLowerCase())) {
              await _repo.createDepartment(n);
            }
          }
        case ObStep.workflow:
          await _repo.applyWorkflowPreset(_preset);
        case ObStep.people:
          for (final i in _invites) {
            if (i.name.text.trim().isNotEmpty &&
                i.email.text.trim().isNotEmpty) {
              await _repo.inviteEmployee(
                name: i.name.text.trim(),
                email: i.email.text.trim(),
                role: i.role.value,
              );
            }
          }
        case ObStep.plan:
          final id = _planId;
          if (id != null && id != _session.company.value?.plan?.id) {
            await _repo.subscribe(id);
          }
      }
      return true;
    } catch (e) {
      _report(e);
      return false;
    }
  }

  Future<void> _advance() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final ok = await _persist();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;

    if (_index == _steps.length - 1) {
      try {
        await _session.refresh();
      } catch (_) {}
      final name = _session.company.value?.name ?? 'auth.ob.yourCompany'.tr;
      showToast(
        'auth.ob.done'.tr,
        body: 'auth.ob.doneBody'.trParams({'name': name}),
      );
      Get.offAllNamed(Routes.shell);
      return;
    }
    setState(() => _index++);
    _toTop();
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _addDept() {
    final n = _newDept.text.trim();
    if (n.isEmpty) return;
    setState(() => _departments.add(n));
    _newDept.clear();
  }

  Future<void> _pickLogo() async {
    final (picked, problem) = await pickCompanyLogo();
    if (!mounted) return;
    setState(() {
      if (problem != null) {
        _logoError = problem == LogoProblem.type
            ? 'auth.rg.badLogoType'.tr
            : 'auth.rg.badLogoSize'.tr;
      } else if (picked != null) {
        _logo = picked;
        _logoError = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_session.isSignedIn) {
      return Scaffold(body: Center(child: Text('auth.loading'.tr)));
    }
    final t = context.vf;
    final last = _index == _steps.length - 1;

    return AuthFrame(
      scrollController: _scroll,
      kicker: 'auth.ob.kicker'.tr,
      title: 'auth.ob.step.${_step.name}'.tr,
      sub: 'auth.ob.stepOf'.trParams({
        'n': '${_index + 1}',
        'total': '${_steps.length}',
      }),
      aside: _Checklist(index: _index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      height: 3,
                      color: i <= _index ? t.primary : t.borderStrong,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          ..._fields(context),
          const SizedBox(height: 24),
          Divider(height: 1, color: t.border),
          const SizedBox(height: 16),
          VouchFlowButton(
            label: last ? 'auth.ob.finish'.tr : 'auth.ob.next'.tr,
            loading: _busy,
            expand: true,
            height: 48,
            onPressed: _busy ? null : _advance,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              VouchFlowButton(
                label: 'auth.ob.back'.tr,
                variant: VfButtonVariant.secondary,
                compact: true,
                onPressed: _index == 0 || _busy
                    ? null
                    : () {
                        setState(() => _index--);
                        _toTop();
                      },
              ),
              const Spacer(),
              Flexible(
                child: VouchFlowButton(
                  label: 'auth.ob.skip'.tr,
                  variant: VfButtonVariant.ghost,
                  compact: true,
                  onPressed: _busy ? null : () => Get.offAllNamed(Routes.shell),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _fields(BuildContext context) {
    final t = context.vf;
    switch (_step) {
      case ObStep.company:
        return [
          VouchFlowTextField(
            label: 'auth.ob.address'.tr,
            controller: _address,
            placeholder: 'auth.ob.addressPh'.tr,
            autofillHints: const [AutofillHints.fullStreetAddress],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          VouchFlowTextField(
            label: 'auth.ob.phone'.tr,
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          VouchFlowTextField(
            label: 'auth.ob.website'.tr,
            controller: _website,
            placeholder: 'https://',
            keyboardType: TextInputType.url,
            autofillHints: const [AutofillHints.url],
          ),
        ];
      case ObStep.logo:
        return [
          VouchFlowField(
            label: 'auth.ob.logo'.tr,
            hint: 'auth.ob.logoHint'.tr,
            error: _logoError,
            child: Row(
              children: [
                VouchFlowButton(
                  label: 'auth.ob.chooseFile'.tr,
                  icon: PhosphorIconsRegular.uploadSimple,
                  variant: VfButtonVariant.secondary,
                  compact: true,
                  onPressed: _busy ? null : _pickLogo,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _logo?.name ?? 'auth.ob.noFile'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VfType.small.copyWith(
                      color: _logo == null ? t.muted : t.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ColourField(
            label: 'auth.ob.primaryColour'.tr,
            controller: _colour,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final hex in _swatches)
                Semantics(
                  button: true,
                  label: 'auth.ob.useColour'.trParams({'colour': hex}),
                  child: InkWell(
                    onTap: () => setState(() => _colour.text = hex),
                    borderRadius: BorderRadius.circular(VfSize.radiusM),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: colourFromHex(hex),
                          borderRadius: BorderRadius.circular(VfSize.radiusM),
                          border: Border.all(
                            color: _colour.text.toUpperCase() == hex
                                ? t.text
                                : t.border,
                            width: _colour.text.toUpperCase() == hex ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ];
      case ObStep.departments:
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AuthInput(
                  controller: _newDept,
                  placeholder: 'auth.ob.addDept'.tr,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _addDept(),
                  semanticLabel: 'auth.ob.addDept'.tr,
                ),
              ),
              const SizedBox(width: 8),
              VouchFlowButton(
                label: 'auth.ob.add'.tr,
                variant: VfButtonVariant.secondary,
                height: VfSize.inputH,
                onPressed: _addDept,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _departments.length; i++)
                Container(
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    color: t.surface3,
                    borderRadius: BorderRadius.circular(VfSize.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _departments[i],
                          overflow: TextOverflow.ellipsis,
                          style: VfType.small.copyWith(
                            fontWeight: FontWeight.w500,
                            color: t.text,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'auth.ob.removeDept'.trParams({
                          'name': _departments[i],
                        }),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        icon: Icon(
                          PhosphorIconsRegular.x,
                          size: 13,
                          color: t.text2,
                        ),
                        onPressed: () =>
                            setState(() => _departments.removeAt(i)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ];
      case ObStep.workflow:
        return [
          Text(
            'auth.ob.wfIntro'.tr,
            style: VfType.small.copyWith(fontSize: 14.5, color: t.text2),
          ),
          const SizedBox(height: 12),
          for (final p in _presets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RadioCard(
                selected: _preset == p.key,
                title: p.name,
                subtitle: p.description,
                onTap: () => setState(() => _preset = p.key),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'auth.ob.wfLater'.tr,
            style: VfType.meta.copyWith(fontSize: 13, color: t.muted),
          ),
        ];
      case ObStep.people:
        return [
          for (var i = 0; i < _invites.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: t.border),
              const SizedBox(height: 10),
            ],
            AuthInput(
              controller: _invites[i].name,
              placeholder: 'auth.ob.fullName'.tr,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              semanticLabel: 'auth.ob.fullName'.tr,
            ),
            const SizedBox(height: 8),
            AuthInput(
              controller: _invites[i].email,
              placeholder: 'auth.ob.email'.tr,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              semanticLabel: 'auth.ob.email'.tr,
            ),
            const SizedBox(height: 8),
            Obx(
              () => DropdownButtonFormField<String>(
                initialValue: _invites[i].role.value,
                isExpanded: true,
                icon: Icon(
                  PhosphorIconsRegular.caretDown,
                  size: 16,
                  color: t.muted,
                ),
                dropdownColor: t.surface,
                style: VfType.body.copyWith(color: t.text),
                decoration: InputDecoration(filled: true, fillColor: t.inputBg),
                items: [
                  for (final r in _roles)
                    DropdownMenuItem(
                      value: r,
                      child: Text(
                        'auth.ob.role.$r'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => _invites[i].role.value = v ?? 'employee',
              ),
            ),
          ],
          const SizedBox(height: 12),
          VouchFlowButton(
            label: 'auth.ob.inviteUser'.tr,
            icon: PhosphorIconsRegular.plus,
            variant: VfButtonVariant.secondary,
            onPressed: () =>
                setState(() => _invites.add(_Invite(role: 'employee'))),
          ),
        ];
      case ObStep.plan:
        return [
          for (final plan in _plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RadioCard(
                selected: _planId == plan.id,
                title: plan.label,
                subtitle:
                    '${plan.maxUsers != null && plan.maxUsers! > 0 ? 'auth.ob.users'.trParams({'n': '${plan.maxUsers}'}) : 'auth.ob.unlimitedUsers'.tr} · '
                    '${plan.maxVouchers != null && plan.maxVouchers! > 0 ? 'auth.ob.vouchers'.trParams({'n': '${plan.maxVouchers}'}) : 'auth.ob.unlimitedVouchers'.tr}',
                onTap: () => setState(() => _planId = plan.id),
              ),
            ),
          Text(
            'auth.ob.trialNote'.tr,
            style: VfType.meta.copyWith(fontSize: 13, color: t.muted),
          ),
        ];
    }
  }
}

/// A radio choice with a title and a line under it (workflow presets, plans).
class _RadioCard extends StatelessWidget {
  const _RadioCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected ? t.primarySoft : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusM),
          side: BorderSide(color: selected ? t.primary : t.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected
                        ? PhosphorIconsFill.radioButton
                        : PhosphorIconsRegular.circle,
                    size: 20,
                    color: selected ? t.primary : t.faint,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: VfType.bodyStrong.copyWith(color: t.text),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: VfType.small.copyWith(color: t.text2),
                        ),
                    ],
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

/// The setup checklist beside (on a phone, below) the card.
class _Checklist extends StatelessWidget {
  const _Checklist({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(VfSize.radiusM),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'auth.ob.checklist'.tr.toUpperCase(),
            style: VfType.eyebrow.copyWith(fontSize: 12, color: t.muted),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < ObStep.values.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Icon(
                    i < index
                        ? PhosphorIconsRegular.checkCircle
                        : i == index
                        ? PhosphorIconsRegular.circleHalf
                        : PhosphorIconsRegular.circle,
                    size: 18,
                    color: i < index
                        ? t.primary
                        : (i == index ? t.text : t.muted),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'auth.ob.step.${ObStep.values[i].name}'.tr,
                      style: VfType.small.copyWith(
                        fontSize: 14.5,
                        color: i <= index ? t.text : t.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

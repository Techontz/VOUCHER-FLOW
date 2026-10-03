import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/auth_repository.dart';
import '../../data/services/session_service.dart';
import '../../data/services/template_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import 'auth_widgets.dart';
import 'brand_inputs.dart';
import 'verify_account_page.dart';

/*
 * Setting a company up on VouchFlow — the web's /register.
 *
 * Five short steps, and nothing is sent until the last one. Then, in order:
 *   1. POST /auth/register — company, administrator, plan and the chosen
 *      voucher template. The only call that can fail the registration.
 *   2. PUT /company        — trading name, TIN, contact details and colours.
 *   3. POST /company/logo  — the logo.
 * Steps 2 and 3 run as the new administrator; if either is refused the
 * company still exists and the outcome says what to finish in Settings.
 */

enum RegStep { company, contact, branding, admin, review }

/// Which step owns each server-side field, so a refusal takes the person to it.
const _fieldStep = {
  'company_name': 0,
  'country': 0,
  'currency': 0,
  'trading_name': 0,
  'tin': 0,
  'registration_number': 0,
  'business_email': 1,
  'phone': 1,
  'address': 1,
  'contact_person': 1,
  'city': 1,
  'region': 1,
  'primary_color': 2,
  'secondary_color': 2,
  'logo': 2,
  'voucher_template': 2,
  'name': 3,
  'email': 3,
  'password': 3,
  'password_confirmation': 3,
  'plan_code': 4,
};

const _regions = [
  'Arusha',
  'Dar es Salaam',
  'Dodoma',
  'Geita',
  'Iringa',
  'Kagera',
  'Katavi',
  'Kigoma',
  'Kilimanjaro',
  'Lindi',
  'Manyara',
  'Mara',
  'Mbeya',
  'Morogoro',
  'Mtwara',
  'Mwanza',
  'Njombe',
  'Pemba North',
  'Pemba South',
  'Pwani',
  'Rukwa',
  'Ruvuma',
  'Shinyanga',
  'Simiyu',
  'Singida',
  'Songwe',
  'Tabora',
  'Tanga',
  'Zanzibar North',
  'Zanzibar South',
  'Zanzibar Urban West',
];

const _countries = {
  'TZ': 'Tanzania',
  'KE': 'Kenya',
  'UG': 'Uganda',
  'RW': 'Rwanda',
  'ZA': 'South Africa',
};
const _currencies = ['TZS', 'KES', 'UGX', 'USD', 'EUR'];

final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// What happened after the company was created.
enum SaveState { ok, failed, skipped }

class RegOutcome {
  const RegOutcome({
    required this.details,
    required this.logo,
    required this.company,
    required this.identifier,
    this.requiresVerification = true,
  });
  final SaveState details, logo;
  final String company, identifier;

  /// False when the server registered the company without an e-mail code.
  final bool requiresVerification;
}

class RegisterController extends GetxController {
  final _repo = AuthRepository.to;
  final _templates = TemplateRepository.to;
  final _session = Get.find<SessionService>();

  final step = 0.obs;
  final plans = <Plan>[].obs;
  final planCode = 'business'.obs;
  final errors = <String, String>{}.obs;
  final serverMessage = RxnString();
  final busy = false.obs;
  final outcome = Rxn<RegOutcome>();
  final reveal = false.obs;

  final companyName = TextEditingController();
  final tradingName = TextEditingController();
  final tin = TextEditingController();
  final regNo = TextEditingController();
  final country = 'TZ'.obs;
  final currency = 'TZS'.obs;
  final contactPerson = TextEditingController();
  final businessEmail = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final city = TextEditingController();
  final region = TextEditingController();
  final primary = TextEditingController(text: '#2563EB');
  final secondary = TextEditingController(text: '#0B1D3A');
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();

  /// The password as typed, for the strength meter.
  final passwordText = ''.obs;

  final logo = Rxn<PickedLogo>();

  // The design catalogue and the sample vouchers in the brand typed so far.
  final templates = <VoucherTemplate>[].obs;
  String defaultKey = 'classic';
  final catalogueFailed = false.obs;
  final catalogueLoading = true.obs;
  final voucherTemplate = RxnString();
  final previews = <String, String>{}.obs;
  final previewsLoading = false.obs;
  final previewsFailed = false.obs;
  String? _placeholder;

  /// The logo placeholder swapped for the picked logo; replaced (never
  /// mutated) so documents reload only when it changes.
  final replacements = Rx<Map<String, String>>(const {});

  Timer? _debounce;
  String? _lastPreviewKey;

  static const steps = RegStep.values;

  @override
  void onInit() {
    super.onInit();
    unawaited(_loadPlans());
    unawaited(_loadCatalogue());
    password.addListener(() => passwordText.value = password.text);
    ever(_session.locale, (_) => _schedulePreviews());
  }

  Future<void> _loadPlans() async {
    try {
      plans.assignAll(await _repo.plans());
    } catch (_) {
      plans.clear();
    }
  }

  Future<void> _loadCatalogue() async {
    catalogueLoading.value = true;
    try {
      final (list, def) = await _templates.catalogue();
      templates.assignAll(list);
      defaultKey = def;
      catalogueFailed.value = false;
    } catch (_) {
      catalogueFailed.value = true;
    } finally {
      catalogueLoading.value = false;
    }
  }

  String _trim(TextEditingController c) => c.text.trim();
  String? _orNull(String v) => v.isEmpty ? null : v;

  /// Refetches the samples (debounced) once the branding step is reached.
  void _schedulePreviews() {
    if (step.value < 2) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _fetchPreviews);
  }

  Future<void> _fetchPreviews() async {
    final brand = {
      'name': _orNull(
        _trim(tradingName).isNotEmpty ? _trim(tradingName) : _trim(companyName),
      ),
      'address': _orNull(
        [
          address,
          city,
          region,
        ].map(_trim).where((v) => v.isNotEmpty).join(', '),
      ),
      'phone': _orNull(_trim(phone)),
      'email': _orNull(_trim(businessEmail)),
      'tin': _orNull(_trim(tin)),
      'primary': isHexColour(primary.text) ? primary.text : null,
      'secondary': isHexColour(secondary.text) ? secondary.text : null,
      'locale': _session.locale.value,
      'logo': logo.value != null,
    };
    final key = jsonEncode(brand);
    if (key == _lastPreviewKey && previews.isNotEmpty) return;
    _lastPreviewKey = key;
    previewsLoading.value = true;
    try {
      final result = await _templates.samplePreviews(
        locale: brand['locale'] as String,
        name: brand['name'] as String?,
        address: brand['address'] as String?,
        phone: brand['phone'] as String?,
        email: brand['email'] as String?,
        tin: brand['tin'] as String?,
        primaryColor: brand['primary'] as String?,
        secondaryColor: brand['secondary'] as String?,
        withLogo: brand['logo'] as bool,
      );
      if (key != _lastPreviewKey) return;
      _placeholder = result.logoPlaceholder;
      previews.assignAll(result.html);
      previewsFailed.value = false;
      _updateReplacements();
    } catch (_) {
      if (key == _lastPreviewKey) {
        previewsFailed.value = true;
        _lastPreviewKey = null;
      }
    } finally {
      previewsLoading.value = false;
    }
  }

  void _updateReplacements() {
    final l = logo.value;
    final p = _placeholder;
    replacements.value = l != null && p != null && p.isNotEmpty
        ? {p: 'data:${l.mime};base64,${base64Encode(l.bytes)}'}
        : const {};
  }

  void onColourChanged() => _schedulePreviews();

  /// After "Previews are unavailable": fetch the catalogue and samples again.
  Future<void> retryPreviews() async {
    if (catalogueFailed.value) await _loadCatalogue();
    _lastPreviewKey = null;
    _schedulePreviews();
  }

  void clearError(String key) {
    if (errors.containsKey(key)) errors.remove(key);
  }

  Map<String, String> problemsAt(int index) {
    final out = <String, String>{};
    void req(String key, TextEditingController c) {
      if (_trim(c).isEmpty) out[key] = 'auth.rg.required'.tr;
    }

    if (index == 0) req('company_name', companyName);
    if (index == 1) {
      req('contact_person', contactPerson);
      if (_trim(businessEmail).isEmpty) {
        out['business_email'] = 'auth.rg.required'.tr;
      } else if (!_email.hasMatch(_trim(businessEmail))) {
        out['business_email'] = 'auth.rg.badEmail'.tr;
      }
    }
    if (index == 2) {
      if (!isHexColour(primary.text)) {
        out['primary_color'] = 'auth.rg.badColour'.tr;
      }
      if (!isHexColour(secondary.text)) {
        out['secondary_color'] = 'auth.rg.badColour'.tr;
      }
      if (voucherTemplate.value == null && templates.isNotEmpty) {
        out['voucher_template'] = 'auth.rg.chooseTemplate'.tr;
      }
    }
    if (index == 3) {
      req('name', name);
      if (_trim(email).isEmpty) {
        out['email'] = 'auth.rg.required'.tr;
      } else if (!_email.hasMatch(_trim(email))) {
        out['email'] = 'auth.rg.badEmail'.tr;
      }
      if (password.text.length < 8) {
        out['password'] = 'auth.rg.shortPassword'.tr;
      }
      if (confirm.text != password.text) {
        out['password_confirmation'] = 'auth.rg.mismatch'.tr;
      }
    }
    return out;
  }

  /// Moves to [next], checking every step passed on the way.
  /// Returns false when a step needs attention (and shows it).
  bool go(int next) {
    if (next > step.value) {
      for (var i = step.value; i < next; i++) {
        final problems = problemsAt(i);
        if (problems.isNotEmpty) {
          errors.assignAll(problems);
          step.value = i;
          return false;
        }
      }
    }
    errors.clear();
    serverMessage.value = null;
    step.value = next;
    _schedulePreviews();
    return true;
  }

  Future<void> pickLogo() async {
    final (picked, problem) = await pickCompanyLogo();
    if (problem != null) {
      errors.assignAll({
        'logo': problem == LogoProblem.type
            ? 'auth.rg.badLogoType'.tr
            : 'auth.rg.badLogoSize'.tr,
      });
      return;
    }
    if (picked == null) return;
    errors.clear();
    logo.value = picked;
    _updateReplacements();
    _schedulePreviews();
  }

  void removeLogo() {
    logo.value = null;
    _updateReplacements();
    _schedulePreviews();
  }

  void chooseTemplate(String key) {
    voucherTemplate.value = key;
    clearError('voucher_template');
  }

  VoucherTemplate? get chosen =>
      templates.firstWhereOrNull((t) => t.key == voucherTemplate.value);

  String templateName(String locale) => chosen?.name(locale) ?? '—';

  Plan? get selectedPlan =>
      plans.firstWhereOrNull((p) => p.code == planCode.value);

  /// Creates the company, then saves the details and logo as the new
  /// administrator; [outcome] reports each part.
  Future<void> create() async {
    if (busy.value) return;
    busy.value = true;
    serverMessage.value = null;

    final Registration res;
    try {
      res = await _repo.register({
        'company_name': _trim(companyName),
        'business_email': _trim(businessEmail),
        'phone': _orNull(_trim(phone)),
        'address': _orNull(_trim(address)),
        'country': country.value,
        'currency': currency.value,
        'locale': _session.locale.value,
        'name': _trim(name),
        'email': _trim(email),
        'password': password.text,
        'password_confirmation': confirm.text,
        'plan_code': planCode.value,
        'voucher_template': voucherTemplate.value ?? defaultKey,
      });
    } on ApiException catch (e) {
      busy.value = false;
      final fieldErrors = e.errors.map((k, v) => MapEntry(k, v.first));
      errors.assignAll(fieldErrors);
      serverMessage.value = fieldErrors.isNotEmpty
          ? 'auth.rg.fixErrors'.tr
          : e.message;
      final stepsHit = fieldErrors.keys
          .map((k) => _fieldStep[k])
          .whereType<int>();
      if (stepsHit.isNotEmpty) {
        step.value = stepsHit.reduce((a, b) => a < b ? a : b);
      }
      return;
    } catch (_) {
      busy.value = false;
      serverMessage.value = 'state.offline'.tr;
      return;
    }

    try {
      await _session.startSessionFrom(res.raw);
    } catch (_) {
      // The token is stored; the profile loads on the next screen.
    }

    final details = <String, String>{
      'trading_name': _trim(tradingName),
      'tin': _trim(tin),
      'registration_number': _trim(regNo),
      'contact_person': _trim(contactPerson),
      'contact_email': _trim(businessEmail),
      'contact_phone': _trim(phone),
      'city': _trim(city),
      'region': _trim(region),
      'primary_color': primary.text.trim().toUpperCase(),
      'secondary_color': secondary.text.trim().toUpperCase(),
    }..removeWhere((_, v) => v.isEmpty);

    var detailsState = SaveState.ok;
    try {
      await _repo.updateCompany(details);
    } catch (_) {
      detailsState = SaveState.failed;
    }

    var logoState = SaveState.skipped;
    final l = logo.value;
    if (l != null) {
      try {
        await _repo.uploadLogo(l);
        logoState = SaveState.ok;
      } catch (_) {
        logoState = SaveState.failed;
      }
    }

    outcome.value = RegOutcome(
      details: detailsState,
      logo: logoState,
      company: res.company.name,
      identifier: res.otpIdentifier,
      requiresVerification: res.requiresVerification,
    );
    busy.value = false;
  }

  @override
  void onClose() {
    _debounce?.cancel();
    for (final c in [
      companyName,
      tradingName,
      tin,
      regNo,
      contactPerson,
      businessEmail,
      phone,
      address,
      city,
      region,
      primary,
      secondary,
      name,
      email,
      password,
      confirm,
    ]) {
      c.dispose();
    }
    super.onClose();
  }
}

/// Company registration.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  late final RegisterController c = Get.put(RegisterController());
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    Get.delete<RegisterController>();
    super.dispose();
  }

  void _toTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _go(int next) {
    FocusScope.of(context).unfocus();
    c.go(next);
    _toTop();
  }

  Future<void> _confirm() async {
    FocusScope.of(context).unfocus();
    final locale = Get.locale?.languageCode ?? 'en';
    final plan = c.selectedPlan;
    await showVouchFlowDialog<void>(
      context,
      dialog: VouchFlowDialog(
        title: 'auth.rg.confirmTitle'.tr,
        subtitle: 'auth.rg.confirmSub'.tr,
        icon: PhosphorIconsRegular.buildings,
        tone: VfTone.info,
        summary: [
          VfSummaryRow(
            'auth.rg.companyName'.tr,
            c.tradingName.text.trim().isEmpty
                ? c.companyName.text.trim()
                : '${c.companyName.text.trim()} (${c.tradingName.text.trim()})',
          ),
          VfSummaryRow('auth.rg.adminEmail'.tr, c.email.text.trim()),
          VfSummaryRow('auth.rg.template'.tr, c.templateName(locale)),
          VfSummaryRow(
            'auth.rg.plan'.tr,
            plan == null
                ? c.planCode.value
                : '${plan.label} · ${plan.trialDays} ${'auth.rg.trial'.tr}',
          ),
        ],
        actions: [
          Builder(
            builder: (ctx) => Obx(
              () => VouchFlowButton(
                label: 'auth.rg.cancel'.tr,
                variant: VfButtonVariant.secondary,
                onPressed: c.busy.value ? null : () => Navigator.of(ctx).pop(),
              ),
            ),
          ),
          Builder(
            builder: (ctx) => Obx(
              () => VouchFlowButton(
                label: c.busy.value
                    ? 'auth.rg.creating'.tr
                    : 'auth.rg.create'.tr,
                loading: c.busy.value,
                onPressed: c.busy.value
                    ? null
                    : () async {
                        await c.create();
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        _toTop();
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _preview(String key) async {
    final picked = await showTemplatePreview(
      context,
      templates: c.templates,
      previews: Map.of(c.previews),
      initialKey: key,
      selected: c.voucherTemplate.value,
      note: 'auth.rg.templateOnce'.tr,
      replacements: c.replacements.value,
    );
    if (picked != null) c.chooseTemplate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Obx(() {
      final done = c.outcome.value;
      final step = c.step.value;
      final onReview = step == RegisterController.steps.length - 1;
      final wide = RegisterController.steps[step] == RegStep.branding;

      return PopScope(
        canPop: !c.busy.value && done == null,
        onPopInvokedWithResult: (didPop, _) {
          // Once the company exists its administrator is signed in: leaving
          // the outcome opens the app rather than the sign-in screen.
          if (!didPop && done != null) Get.offAllNamed(Routes.shell);
        },
        child: Scaffold(
          backgroundColor: t.background,
          bottomNavigationBar: done != null
              ? null
              : _NavBar(
                  back: step > 0 ? () => _go(step - 1) : null,
                  primaryLabel: onReview
                      ? 'auth.rg.create'.tr
                      : 'auth.rg.continue'.tr,
                  primaryIcon: onReview ? PhosphorIconsRegular.buildings : null,
                  primaryTrailing: onReview
                      ? null
                      : PhosphorIconsRegular.arrowRight,
                  onPrimary: onReview ? _confirm : () => _go(step + 1),
                ),
          body: SafeArea(
            bottom: done != null,
            child: SingleChildScrollView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: done == null && wide ? 1120 : 680,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (done == null && Navigator.of(context).canPop())
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: AuthBackButton(
                                onTap: c.busy.value
                                    ? null
                                    : () => Navigator.of(context).maybePop(),
                              ),
                            ),
                          const Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: VfBrandMark(size: 40),
                            ),
                          ),
                          const AuthTools(),
                        ],
                      ),
                      if (done != null) ...[
                        const SizedBox(height: 14),
                        _Outcome(outcome: done),
                      ] else ...[
                        const SizedBox(height: 14),
                        _Progress(step: step),
                        const SizedBox(height: 14),
                        AuthCard(
                          padding: const EdgeInsets.fromLTRB(18, 26, 18, 22),
                          child: _StepBody(
                            c: c,
                            onPreview: _preview,
                            onEdit: _go,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          children: [
                            Text(
                              'auth.rg.already'.tr,
                              style: VfType.body.copyWith(
                                fontSize: 14,
                                color: t.muted,
                              ),
                            ),
                            AuthLink(
                              'auth.rg.signIn'.tr,
                              onTap: () => Get.back(),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final total = RegisterController.steps.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'auth.rg.stepOf'.trParams({
                  'n': '${step + 1}',
                  'total': '$total',
                }),
                style: VfType.small.copyWith(color: t.muted),
              ),
            ),
            Expanded(
              child: Text(
                'auth.rg.step.${RegisterController.steps[step].name}'.tr,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VfType.small.copyWith(
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: t.isDark ? t.surface3 : t.border),
                ),
                AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  widthFactor: (step + 1) / total,
                  heightFactor: 1,
                  alignment: Alignment.centerLeft,
                  child: ColoredBox(color: t.primary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The fixed bar at the foot of the screen: Back and Continue / Create.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.back,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryIcon,
    this.primaryTrailing,
  });

  final VoidCallback? back;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final IconData? primaryIcon, primaryTrailing;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? .35 : .08),
            blurRadius: 24,
            offset: const Offset(0, -8),
            spreadRadius: -12,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Row(
                children: [
                  if (back != null) ...[
                    Expanded(
                      flex: 2,
                      child: VouchFlowButton(
                        label: 'auth.rg.back'.tr,
                        icon: PhosphorIconsRegular.arrowLeft,
                        variant: VfButtonVariant.secondary,
                        height: 48,
                        onPressed: back,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 3,
                    child: VouchFlowButton(
                      label: primaryLabel,
                      icon: primaryIcon,
                      trailingIcon: primaryTrailing,
                      height: 48,
                      onPressed: onPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two fields side by side on a tablet, stacked on a phone (the web's `.rg-row`).
class _Pair extends StatelessWidget {
  const _Pair(this.a, this.b);
  final Widget a, b;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => box.maxWidth >= 520
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 16),
              Expanded(child: b),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [a, const SizedBox(height: 20), b],
          ),
  );
}

class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.c,
    required this.onPreview,
    required this.onEdit,
  });

  final RegisterController c;
  final ValueChanged<String> onPreview;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Obx(() {
      final step = RegisterController.steps[c.step.value];
      final fields = switch (step) {
        RegStep.company => _company(context),
        RegStep.contact => _contact(context),
        RegStep.branding => _branding(context),
        RegStep.admin => _admin(context),
        RegStep.review => _review(context),
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'auth.rg.step.${step.name}Title'.tr,
            style: VfType.pageTitle.copyWith(
              fontSize: 22,
              letterSpacing: -.6,
              color: t.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'auth.rg.step.${step.name}Sub'.tr,
            style: VfType.body.copyWith(color: t.muted),
          ),
          if (c.serverMessage.value != null) ...[
            const SizedBox(height: 20),
            VouchFlowAlert(
              message: c.serverMessage.value!,
              tone: VfTone.bad,
              icon: PhosphorIconsRegular.warningCircle,
            ),
          ],
          const SizedBox(height: 26),
          ...fields,
        ],
      );
    });
  }

  String? _e(String key) => c.errors[key];

  Widget _text(
    String key,
    TextEditingController controller, {
    required String label,
    String? hint,
    String? placeholder,
    bool required = false,
    TextInputType? keyboard,
    Iterable<String>? autofill,
    TextCapitalization caps = TextCapitalization.none,
  }) => VouchFlowTextField(
    label: label,
    controller: controller,
    required: required,
    hint: hint,
    placeholder: placeholder,
    error: _e(key),
    keyboardType: keyboard,
    autofillHints: autofill,
    textCapitalization: caps,
    textInputAction: TextInputAction.next,
    onChanged: (_) => c.clearError(key),
  );

  List<Widget> _company(BuildContext context) => [
    _text(
      'company_name',
      c.companyName,
      label: 'auth.rg.companyName'.tr,
      placeholder: 'auth.rg.companyNamePh'.tr,
      required: true,
      autofill: const [AutofillHints.organizationName],
      caps: TextCapitalization.words,
    ),
    const SizedBox(height: 20),
    _text(
      'trading_name',
      c.tradingName,
      label: 'auth.rg.tradingName'.tr,
      hint: 'auth.rg.tradingHint'.tr,
      caps: TextCapitalization.words,
    ),
    const SizedBox(height: 20),
    _Pair(
      _text(
        'tin',
        c.tin,
        label: 'auth.rg.tin'.tr,
        hint: 'auth.rg.tinHint'.tr,
        placeholder: '123-456-789',
        keyboard: TextInputType.phone,
      ),
      _text(
        'registration_number',
        c.regNo,
        label: 'auth.rg.regNo'.tr,
        hint: 'auth.rg.regHint'.tr,
        placeholder: 'BRELA 145678',
      ),
    ),
    const SizedBox(height: 20),
    _Pair(
      VouchFlowDropdown<String>(
        label: 'auth.rg.country'.tr,
        items: _countries.keys.toList(),
        value: c.country.value,
        itemLabel: (k) => _countries[k]!,
        onChanged: (v) => c.country.value = v ?? 'TZ',
      ),
      VouchFlowDropdown<String>(
        label: 'auth.rg.currency'.tr,
        items: _currencies,
        value: c.currency.value,
        itemLabel: (k) => k,
        onChanged: (v) => c.currency.value = v ?? 'TZS',
      ),
    ),
  ];

  List<Widget> _contact(BuildContext context) => [
    _text(
      'contact_person',
      c.contactPerson,
      label: 'auth.rg.contactPerson'.tr,
      required: true,
      autofill: const [AutofillHints.name],
      caps: TextCapitalization.words,
    ),
    const SizedBox(height: 20),
    _Pair(
      _text(
        'business_email',
        c.businessEmail,
        label: 'auth.rg.email'.tr,
        placeholder: 'auth.rg.emailPh'.tr,
        required: true,
        keyboard: TextInputType.emailAddress,
        autofill: const [AutofillHints.email],
      ),
      _text(
        'phone',
        c.phone,
        label: 'auth.rg.phone'.tr,
        placeholder: '+255 7xx xxx xxx',
        keyboard: TextInputType.phone,
        autofill: const [AutofillHints.telephoneNumber],
      ),
    ),
    const SizedBox(height: 20),
    _text(
      'address',
      c.address,
      label: 'auth.rg.address'.tr,
      placeholder: 'auth.rg.addressPh'.tr,
      autofill: const [AutofillHints.fullStreetAddress],
    ),
    const SizedBox(height: 20),
    _Pair(
      _text(
        'city',
        c.city,
        label: 'auth.rg.city'.tr,
        autofill: const [AutofillHints.addressCity],
        caps: TextCapitalization.words,
      ),
      _RegionField(
        controller: c.region,
        error: _e('region'),
        onChanged: () => c.clearError('region'),
      ),
    ),
  ];

  List<Widget> _branding(BuildContext context) {
    final t = context.vf;
    return [
      _LogoPicker(c: c),
      const SizedBox(height: 20),
      _Pair(
        ColourField(
          label: 'auth.rg.primary'.tr,
          controller: c.primary,
          error: _e('primary_color'),
          onChanged: (_) {
            c.clearError('primary_color');
            c.onColourChanged();
          },
        ),
        ColourField(
          label: 'auth.rg.secondary'.tr,
          controller: c.secondary,
          error: _e('secondary_color'),
          onChanged: (_) {
            c.clearError('secondary_color');
            c.onColourChanged();
          },
        ),
      ),
      const SizedBox(height: 16),
      Divider(height: 1, color: t.border),
      const SizedBox(height: 16),
      Text(
        'auth.rg.templateTitle'.tr,
        style: VfType.sectionTitle.copyWith(fontSize: 20, color: t.text),
      ),
      const SizedBox(height: 4),
      Text(
        'auth.rg.templateSub'.tr,
        style: VfType.small.copyWith(color: t.muted),
      ),
      const SizedBox(height: 16),
      Obx(() {
        final invalid = _e('voucher_template') != null;
        Widget body;
        if (c.catalogueFailed.value ||
            (c.previewsFailed.value && c.previews.isEmpty)) {
          body = _Unavailable(onRetry: c.retryPreviews);
        } else if (c.templates.isEmpty) {
          body = const VouchFlowLoadingState(rows: 1, rowHeight: 320);
        } else {
          body = VouchFlowTemplateGallery(
            templates: c.templates,
            previews: Map.of(c.previews),
            selected: c.voucherTemplate.value,
            onPreview: onPreview,
            onSelect: c.chooseTemplate,
            replacements: c.replacements.value,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.previewsLoading.value &&
                c.templates.isNotEmpty &&
                c.previews.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'auth.rg.previewsLoading'.tr,
                  style: VfType.meta.copyWith(color: t.muted),
                ),
              ),
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(VfSize.radiusXl),
                border: invalid
                    ? Border.all(color: t.dangerStrong, width: 2)
                    : null,
              ),
              child: Padding(
                padding: EdgeInsets.all(invalid ? 6 : 0),
                child: body,
              ),
            ),
          ],
        );
      }),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(PhosphorIconsRegular.info, size: 14, color: t.muted),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'auth.rg.templateOnce'.tr,
              style: VfType.meta.copyWith(color: t.muted),
            ),
          ),
        ],
      ),
      if (_e('voucher_template') != null) ...[
        const SizedBox(height: 8),
        _InlineError(_e('voucher_template')!),
      ],
    ];
  }

  List<Widget> _admin(BuildContext context) => [
    _text(
      'name',
      c.name,
      label: 'auth.rg.adminName'.tr,
      required: true,
      autofill: const [AutofillHints.name],
      caps: TextCapitalization.words,
    ),
    const SizedBox(height: 20),
    _text(
      'email',
      c.email,
      label: 'auth.rg.adminEmail'.tr,
      hint: 'auth.rg.adminEmailHint'.tr,
      required: true,
      keyboard: TextInputType.emailAddress,
      autofill: const [AutofillHints.username, AutofillHints.email],
    ),
    const SizedBox(height: 20),
    Obx(
      () => _Pair(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VouchFlowTextField(
              label: 'auth.rg.password'.tr,
              controller: c.password,
              required: true,
              obscure: !c.reveal.value,
              hint: 'auth.rg.passwordHint'.tr,
              error: _e('password'),
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              onChanged: (_) => c.clearError('password'),
              suffix: RevealButton(
                revealed: c.reveal.value,
                onTap: c.reveal.toggle,
              ),
            ),
            const SizedBox(height: 6),
            _Meter(value: c.passwordText.value),
          ],
        ),
        VouchFlowTextField(
          label: 'auth.rg.confirm'.tr,
          controller: c.confirm,
          required: true,
          obscure: !c.reveal.value,
          error: _e('password_confirmation'),
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onChanged: (_) => c.clearError('password_confirmation'),
        ),
      ),
    ),
  ];

  List<Widget> _review(BuildContext context) {
    final t = context.vf;
    final locale = Get.locale?.languageCode ?? 'en';
    String v(TextEditingController x) => x.text.trim();
    return [
      _ReviewBlock(
        title: 'auth.rg.step.company'.tr,
        onEdit: () => onEdit(0),
        empty: 'auth.rg.notProvided'.tr,
        rows: [
          ('auth.rg.companyName'.tr, v(c.companyName)),
          ('auth.rg.tradingName'.tr, v(c.tradingName)),
          ('auth.rg.tin'.tr, v(c.tin)),
          ('auth.rg.regNo'.tr, v(c.regNo)),
          (
            '${'auth.rg.country'.tr} · ${'auth.rg.currency'.tr}',
            '${c.country.value} · ${c.currency.value}',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _ReviewBlock(
        title: 'auth.rg.step.contact'.tr,
        onEdit: () => onEdit(1),
        empty: 'auth.rg.notProvided'.tr,
        rows: [
          ('auth.rg.contactPerson'.tr, v(c.contactPerson)),
          ('auth.rg.email'.tr, v(c.businessEmail)),
          ('auth.rg.phone'.tr, v(c.phone)),
          (
            'auth.rg.address'.tr,
            [
              v(c.address),
              v(c.city),
              v(c.region),
            ].where((s) => s.isNotEmpty).join(', '),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _ReviewBlock(
        title: 'auth.rg.step.branding'.tr,
        onEdit: () => onEdit(2),
        empty: 'auth.rg.none'.tr,
        rows: [
          ('auth.rg.logo'.tr, c.logo.value?.name ?? ''),
          ('auth.rg.primary'.tr, _Swatch(v(c.primary))),
          ('auth.rg.secondary'.tr, _Swatch(v(c.secondary))),
          ('auth.rg.template'.tr, c.templateName(locale)),
        ],
      ),
      const SizedBox(height: 16),
      _ReviewBlock(
        title: 'auth.rg.step.admin'.tr,
        onEdit: () => onEdit(3),
        empty: 'auth.rg.notProvided'.tr,
        rows: [
          ('auth.rg.adminName'.tr, v(c.name)),
          ('auth.rg.adminEmail'.tr, v(c.email)),
          ('auth.rg.password'.tr, '••••••••'),
        ],
      ),
      if (c.plans.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('auth.rg.plan'.tr, style: VfType.label.copyWith(color: t.text2)),
        const SizedBox(height: 8),
        for (final plan in c.plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PlanOption(
              plan: plan,
              selected: c.planCode.value == plan.code,
              onTap: () => c.planCode.value = plan.code,
            ),
          ),
      ],
    ];
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            PhosphorIconsRegular.warningCircle,
            size: 15,
            color: t.dangerStrong,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: VfType.meta.copyWith(color: t.dangerStrong),
          ),
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => VouchFlowErrorState(
    message: 'auth.rg.previewsUnavailable'.tr,
    onRetry: onRetry,
    retryLabel: 'common.retry'.tr,
  );
}

/// Region with the regions of Tanzania suggested (the web's datalist).
class _RegionField extends StatefulWidget {
  const _RegionField({
    required this.controller,
    required this.error,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String? error;
  final VoidCallback onChanged;

  @override
  State<_RegionField> createState() => _RegionFieldState();
}

class _RegionFieldState extends State<_RegionField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        return q.isEmpty
            ? _regions
            : _regions.where((r) => r.toLowerCase().contains(q));
      },
      fieldViewBuilder: (context, controller, focus, onSubmit) =>
          VouchFlowTextField(
            label: 'auth.rg.region'.tr,
            controller: controller,
            focusNode: focus,
            error: widget.error,
            autofillHints: const [AutofillHints.addressState],
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => widget.onChanged(),
            onSubmitted: (_) => onSubmit(),
          ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: t.surface,
          elevation: 6,
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              children: [
                for (final o in options)
                  InkWell(
                    onTap: () => onSelected(o),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Text(
                        o,
                        style: VfType.body.copyWith(color: t.text),
                      ),
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

/// The logo drop area: a preview box, the name and rules, Choose / Remove.
class _LogoPicker extends StatelessWidget {
  const _LogoPicker({required this.c});
  final RegisterController c;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Obx(() {
      final logo = c.logo.value;
      final error = c.errors['logo'];
      final box = Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: t.surface2,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(8),
        child: logo == null
            ? Icon(PhosphorIconsRegular.imageSquare, size: 28, color: t.faint)
            : Image.memory(
                logo.bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
      );
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            logo?.name ?? 'auth.rg.chooseLogo'.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VfType.bodyStrong.copyWith(color: t.text),
          ),
          const SizedBox(height: 4),
          Text(
            'auth.rg.logoHint'.tr,
            style: VfType.small.copyWith(color: t.muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VouchFlowButton(
                label: logo == null
                    ? 'auth.rg.chooseLogo'.tr
                    : 'auth.rg.replace'.tr,
                icon: PhosphorIconsRegular.uploadSimple,
                variant: VfButtonVariant.secondary,
                compact: true,
                onPressed: c.pickLogo,
              ),
              if (logo != null)
                VouchFlowButton(
                  label: 'auth.rg.remove'.tr,
                  variant: VfButtonVariant.ghost,
                  compact: true,
                  onPressed: c.removeLogo,
                ),
            ],
          ),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('auth.rg.logo'.tr, style: VfType.label.copyWith(color: t.text2)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                color: error != null ? t.dangerStrong : t.borderStrong,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: LayoutBuilder(
              builder: (context, b) => b.maxWidth >= 420
                  ? Row(
                      children: [
                        box,
                        const SizedBox(width: 18),
                        Expanded(child: text),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [box, const SizedBox(height: 14), text],
                    ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            _InlineError(error),
          ],
        ],
      );
    });
  }
}

/// Four bars for the password's strength (the web's `.rg-meter`).
class _Meter extends StatelessWidget {
  const _Meter({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final score = value.isEmpty
        ? 0
        : [
            value.length >= 8,
            value.length >= 12,
            RegExp('[A-Z]').hasMatch(value) && RegExp('[a-z]').hasMatch(value),
            RegExp(r'\d').hasMatch(value) &&
                RegExp('[^A-Za-z0-9]').hasMatch(value),
          ].where((x) => x).length;
    final on = switch (score) {
      1 => t.dangerStrong,
      2 => t.warningStrong,
      _ => t.successStrong,
    };
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var n = 1; n <= 4; n++) ...[
            if (n > 1) const SizedBox(width: 4),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 4,
                decoration: BoxDecoration(
                  color: score >= n ? on : t.surface3,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.value);
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: colourFromHex(value) ?? Colors.transparent,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: VfType.body.copyWith(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: t.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// One step's answers with an Edit link (the web's ReviewBlock).
class _ReviewBlock extends StatelessWidget {
  const _ReviewBlock({
    required this.title,
    required this.rows,
    required this.onEdit,
    required this.empty,
  });

  final String title;

  /// Label and value — a String, or a widget such as a colour swatch.
  final List<(String, Object)> rows;
  final VoidCallback onEdit;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(VfSize.radiusL),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: t.surface2,
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: VfType.bodyStrong.copyWith(color: t.text),
                  ),
                ),
                VouchFlowButton(
                  label: 'auth.rg.edit'.tr,
                  icon: PhosphorIconsRegular.pencilSimple,
                  variant: VfButtonVariant.ghost,
                  compact: true,
                  onPressed: onEdit,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: t.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final (label, value) = rows[i];
                        final labelW = Text(
                          label,
                          style: VfType.small.copyWith(
                            fontSize: 14,
                            color: t.muted,
                          ),
                        );
                        final valueW = value is Widget
                            ? value
                            : (value as String).isEmpty
                            ? Text(
                                empty,
                                style: VfType.small.copyWith(
                                  fontSize: 14,
                                  color: t.faint,
                                ),
                              )
                            : Text(
                                value,
                                style: VfType.body.copyWith(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w500,
                                  color: t.text,
                                ),
                              );
                        if (box.maxWidth < 440) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              labelW,
                              const SizedBox(height: 2),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: valueW,
                              ),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: box.maxWidth * .4, child: labelW),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: valueW,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A plan as a radio card: name, blurb, price and trial (the web's `.rg-plan`).
class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final Plan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final price = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: plan.price > 0
                ? [
                    TextSpan(text: Fmt.money(plan.price, plan.currency)),
                    TextSpan(
                      text: ' ${'auth.rg.perMonth'.tr}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: t.muted,
                      ),
                    ),
                  ]
                : [TextSpan(text: 'auth.rg.custom'.tr)],
          ),
          style: VfType.bodyStrong.copyWith(
            fontSize: 14.5,
            color: t.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          '${plan.trialDays} ${'auth.rg.trial'.tr}',
          style: VfType.meta.copyWith(fontSize: 12, color: t.muted),
        ),
      ],
    );

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: plan.label,
      child: Material(
        color: selected ? t.primarySoft : t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VfSize.radiusL),
          side: BorderSide(
            color: selected ? t.primary : t.borderStrong,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? t.primary : t.surface,
                      border: Border.all(
                        color: selected ? t.primary : t.faint,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: t.surface,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final text = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.label,
                            style: VfType.bodyStrong.copyWith(color: t.text),
                          ),
                          if ((plan.blurb ?? '').isNotEmpty)
                            Text(
                              plan.blurb!,
                              style: VfType.small.copyWith(color: t.muted),
                            ),
                        ],
                      );
                      if (box.maxWidth < 380) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [text, const SizedBox(height: 6), price],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: text),
                          const SizedBox(width: 12),
                          price,
                        ],
                      );
                    },
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

/// The screen after creating the company: what was saved, and Verify email.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.outcome});
  final RegOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;

    Widget line(SaveState state, String label) {
      final ok = state == SaveState.ok;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: ok ? t.successSoft : t.warningSoft,
          borderRadius: BorderRadius.circular(VfSize.radiusL),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ok
                  ? PhosphorIconsRegular.checkCircle
                  : PhosphorIconsRegular.warningCircle,
              size: 20,
              color: ok ? t.success : t.warning,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: VfType.body.copyWith(
                      fontSize: 14.5,
                      color: ok ? t.success : t.warning,
                    ),
                  ),
                  if (state == SaveState.failed)
                    Text(
                      'auth.rg.finishInSettings'.tr,
                      style: VfType.small.copyWith(color: t.warning),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return AuthCard(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 24),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: .6, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutBack,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.successStrong,
                boxShadow: [BoxShadow(color: t.successSoft, spreadRadius: 10)],
              ),
              child: const Icon(
                PhosphorIconsBold.check,
                size: 30,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'auth.rg.doneTitle'.tr,
            textAlign: TextAlign.center,
            style: VfType.pageTitle.copyWith(fontSize: 24, color: t.text),
          ),
          const SizedBox(height: 4),
          Text(
            outcome.company,
            textAlign: TextAlign.center,
            style: VfType.bodyStrong.copyWith(color: t.text2),
          ),
          const SizedBox(height: 8),
          Text(
            outcome.requiresVerification
                ? 'auth.rg.doneSub'.tr
                : 'auth.rg.doneSubPending'.tr,
            textAlign: TextAlign.center,
            style: VfType.body.copyWith(color: t.muted),
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                line(SaveState.ok, 'auth.rg.savedCompany'.tr),
                const SizedBox(height: 8),
                line(outcome.details, 'auth.rg.savedDetails'.tr),
                if (outcome.logo != SaveState.skipped) ...[
                  const SizedBox(height: 8),
                  line(outcome.logo, 'auth.rg.savedLogo'.tr),
                ],
              ],
            ),
          ),
          const SizedBox(height: 26),
          VouchFlowButton(
            label: outcome.requiresVerification
                ? 'auth.rg.verify'.tr
                : 'auth.rg.continue2'.tr,
            trailingIcon: PhosphorIconsRegular.arrowRight,
            height: 54,
            expand: true,
            onPressed: () {
              // Without a code step the administrator goes straight in; the
              // shell shows the waiting screen while the company is pending.
              if (!outcome.requiresVerification) {
                Get.offAllNamed(Routes.shell);
                return;
              }
              final pending =
                  Get.find<SessionService>().company.value?.isPending == true;
              Get.to(
                () => AccountCodePage(
                  purpose: CodePurpose.registration,
                  identifier: outcome.identifier,
                  toOnboarding: !pending,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

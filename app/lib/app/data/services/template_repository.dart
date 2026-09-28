import 'package:get/get.dart';

import 'api_service.dart';

/// One of the ten voucher designs, from the server's catalogue.
class VoucherTemplate {
  VoucherTemplate.fromJson(Map<String, dynamic> j)
    : key = '${j['key']}',
      number = (j['number'] as num?)?.toInt() ?? 0,
      nameEn = '${j['name']}',
      nameSw = '${j['name_sw'] ?? j['name']}',
      descriptionEn = '${j['description'] ?? ''}',
      descriptionSw = '${j['description_sw'] ?? j['description'] ?? ''}',
      isDefault = j['is_default'] == true;

  final String key;
  final int number;
  final String nameEn, nameSw, descriptionEn, descriptionSw;
  final bool isDefault;

  String name(String locale) => locale == 'sw' ? nameSw : nameEn;
  String description(String locale) => locale == 'sw' ? descriptionSw : descriptionEn;
}

/// One recorded change of a company's design.
class VoucherTemplateChange {
  VoucherTemplateChange.fromJson(Map<String, dynamic> j)
    : id = (j['id'] as num?)?.toInt() ?? 0,
      previousTemplate = j['previous_template'] as String?,
      previousName = j['previous_template_name'] as String?,
      newTemplate = '${j['new_template']}',
      newName = '${j['new_template_name'] ?? j['new_template']}',
      changedByName = j['changed_by_name'] as String?,
      changedByRole = j['changed_by_role'] as String?,
      source = '${j['source'] ?? ''}',
      reason = j['reason'] as String?,
      counted = j['counted'] == true,
      createdAt = DateTime.tryParse('${j['created_at']}');

  final int id;
  final String? previousTemplate, previousName;
  final String newTemplate, newName;
  final String? changedByName, changedByRole;
  final String source;
  final String? reason;
  final bool counted;
  final DateTime? createdAt;
}

/// A company's design and what may still be done about it.
class VoucherTemplateState {
  VoucherTemplateState.fromJson(Map<String, dynamic> j)
    : template = '${j['template']}',
      templateName = '${j['template_name'] ?? j['template']}',
      changesUsed = (j['changes_used'] as num?)?.toInt() ?? 0,
      changesAllowed = (j['changes_allowed'] as num?)?.toInt() ?? 1,
      changesRemaining = (j['changes_remaining'] as num?)?.toInt() ?? 0,
      templates = [
        for (final t in (j['templates'] as List? ?? const [])) VoucherTemplate.fromJson(Map<String, dynamic>.from(t as Map)),
      ],
      history = [
        for (final h in (j['history'] as List? ?? const [])) VoucherTemplateChange.fromJson(Map<String, dynamic>.from(h as Map)),
      ];

  final String template, templateName;
  final int changesUsed, changesAllowed, changesRemaining;
  final List<VoucherTemplate> templates;
  final List<VoucherTemplateChange> history;
}

/// Sample vouchers rendered by the server, one per design key, plus the
/// logo placeholder the server prints when the logo lives only on the device.
class TemplatePreviews {
  const TemplatePreviews(this.html, this.logoPlaceholder);
  final Map<String, String> html;
  final String? logoPlaceholder;

  static TemplatePreviews fromJson(dynamic payload) {
    final map = Map<String, dynamic>.from(payload as Map);
    final html = <String, String>{};
    for (final p in (map['data'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(p as Map);
      html['${m['key']}'] = '${m['html']}';
    }
    return TemplatePreviews(html, map['logo_placeholder'] as String?);
  }
}

/// Every voucher-design call the web client makes, in one place: the public
/// catalogue and previews (registration), the company's own design with its
/// one self-service change (Branding), and the platform override.
class TemplateRepository {
  TemplateRepository(this._api);
  final ApiService _api;

  /// Registered once and shared; call from any screen.
  static TemplateRepository get to => Get.isRegistered<TemplateRepository>()
      ? Get.find<TemplateRepository>()
      : Get.put(TemplateRepository(Get.find<ApiService>()), permanent: true);

  Future<(List<VoucherTemplate>, String)> catalogue() async {
    final j = Map<String, dynamic>.from(await _api.get('/voucher-templates') as Map);
    return (
      [for (final t in (j['data'] as List? ?? const [])) VoucherTemplate.fromJson(Map<String, dynamic>.from(t as Map))],
      '${j['default'] ?? 'classic'}',
    );
  }

  /// Public: the sample in every design (or one), in the brand typed so far.
  Future<TemplatePreviews> samplePreviews({
    String? template,
    String? locale,
    String? name,
    String? address,
    String? phone,
    String? email,
    String? website,
    String? tin,
    String? primaryColor,
    String? secondaryColor,
    bool withLogo = false,
  }) async {
    final body = <String, dynamic>{
      'template': ?template,
      'locale': ?locale,
      'name': ?name,
      'address': ?address,
      'phone': ?phone,
      'email': ?email,
      'website': ?website,
      'tin': ?tin,
      'primary_color': ?primaryColor,
      'secondary_color': ?secondaryColor,
      'with_logo': withLogo,
    };
    return TemplatePreviews.fromJson(await _api.post('/voucher-templates/preview', body));
  }

  // ── the signed-in company ──
  Future<VoucherTemplateState> companyState() async =>
      VoucherTemplateState.fromJson(Map<String, dynamic>.from(await _api.get('/company/voucher-template') as Map));

  Future<TemplatePreviews> companyPreviews({String? template, String? locale}) async => TemplatePreviews.fromJson(
    await _api.post('/company/voucher-template/preview', {'template': ?template, 'locale': ?locale}),
  );

  /// Spends the company's self-service change; the server refuses (403) once
  /// it is used.
  Future<VoucherTemplateState> changeCompanyTemplate(String template, {String? reason}) async =>
      VoucherTemplateState.fromJson(
        Map<String, dynamic>.from(await _api.put('/company/voucher-template', {'template': template, 'reason': ?reason}) as Map),
      );

  Future<void> requestChange(String template, String reason) =>
      _api.post('/company/voucher-template/request', {'template': template, 'reason': reason});

  // ── the platform (super admin) ──
  Future<VoucherTemplateState> platformState(int companyId) async => VoucherTemplateState.fromJson(
    Map<String, dynamic>.from(await _api.get('/platform/companies/$companyId/voucher-template') as Map),
  );

  Future<TemplatePreviews> platformPreviews(int companyId, {String? template, String? locale}) async =>
      TemplatePreviews.fromJson(
        await _api.post('/platform/companies/$companyId/voucher-template/preview', {'template': ?template, 'locale': ?locale}),
      );

  Future<VoucherTemplateState> changePlatformTemplate(int companyId, String template, {String? reason}) async =>
      VoucherTemplateState.fromJson(
        Map<String, dynamic>.from(
          await _api.put('/platform/companies/$companyId/voucher-template', {'template': template, 'reason': ?reason}) as Map,
        ),
      );
}

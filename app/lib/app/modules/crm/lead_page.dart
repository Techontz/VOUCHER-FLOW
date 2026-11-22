import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/crm_repository.dart';
import '../../data/services/erp_service.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDateTime;
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import '../inventory/inventory_widgets.dart' show ErpFact;
import 'crm_widgets.dart';

/// Calls or writes to a contact through the phone's own apps.
Future<void> crmContact(String scheme, String value) async {
  final uri = Uri(scheme: scheme, path: scheme == 'tel' ? value.replaceAll(' ', '') : value);
  try {
    await launchUrl(uri);
  } catch (_) {}
}

/// Call / Email buttons for a contact, when there is something to call.
class CrmContactButtons extends StatelessWidget {
  const CrmContactButtons({super.key, this.phone, this.email});

  final String? phone, email;

  @override
  Widget build(BuildContext context) {
    if (phone == null && email == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: VouchFlowActions(
        children: [
          if (phone != null)
            VouchFlowButton(
              label: 'crm.call'.tr,
              icon: PhosphorIconsRegular.phone,
              variant: VfButtonVariant.secondary,
              onPressed: () => crmContact('tel', phone!),
            ),
          if (email != null)
            VouchFlowButton(
              label: 'crm.email'.tr,
              icon: PhosphorIconsRegular.envelopeSimple,
              variant: VfButtonVariant.secondary,
              onPressed: () => crmContact('mailto', email!),
            ),
        ],
      ),
    );
  }
}

/// One lead (the web's /erp/crm/leads/[id]): who, how to reach them, what
/// they might be worth, and their activities. Log an activity or change
/// the status from the foot bar. Opened with the lead id.
class CrmLeadPage extends StatefulWidget {
  const CrmLeadPage({super.key, this.leadId});

  final int? leadId;

  @override
  State<CrmLeadPage> createState() => _CrmLeadPageState();
}

class _CrmLeadPageState extends State<CrmLeadPage> {
  late final int _id = widget.leadId ?? (Get.arguments as int);
  final _repo = CrmRepository.to;
  CrmLead? _lead;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await _repo.lead(_id);
      if (mounted) setState(() { _lead = l; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = opsError(e));
    }
  }

  Future<void> _log(CrmLead l) async {
    await Get.toNamed(Routes.crmActivityNew, arguments: {'lead': l.id, 'name': l.contactName});
    _load();
  }

  Future<void> _status(CrmLead l) async {
    String chosen = l.status;
    final done = await showVfSheet<String>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => VouchFlowDialog(
          icon: PhosphorIconsRegular.flag,
          title: 'crm.changeStatus'.tr,
          subtitle: '${l.number} · ${l.contactName}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in CrmLeadStatus.settable)
                    VouchFlowFilterChip(label: crmLeadStatusLabel(s), selected: chosen == s, onTap: () => set(() => chosen = s)),
                ],
              ),
              const SizedBox(height: 14),
              OpsConfirm(
                key: ValueKey(chosen),
                confirmLabel: 'crm.save'.tr,
                danger: chosen == 'lost',
                fieldLabel: chosen == 'lost' ? 'crm.lostReason'.tr : null,
                minLength: chosen == 'lost' && l.lostReason == null ? 3 : 0,
                ready: chosen != l.status,
                run: (reason) async {
                  await _repo.setLeadStatus(l.id, chosen, lostReason: reason);
                  return chosen;
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (done == null) return;
    showToast(crmLeadStatusLabel(done), body: l.contactName);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = _lead;
    final manage = ErpService.to.can('crm.manage');
    return VouchFlowPushedScaffold(
      title: l?.number ?? 'crm.lead'.tr,
      body: l == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : _body(context, l, manage),
      bottomBar: l == null || !manage || l.isConverted
          ? null
          : OpsActionBar(
              children: [
                VouchFlowButton(label: 'crm.changeStatus'.tr, variant: VfButtonVariant.secondary, onPressed: () => _status(l)),
                VouchFlowButton(label: 'crm.log'.tr, icon: PhosphorIconsRegular.phoneCall, onPressed: () => _log(l)),
              ],
            ),
    );
  }

  Widget _body(BuildContext context, CrmLead l, bool manage) {
    final t = context.vf;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        OpsHead(
          icon: PhosphorIconsRegular.userFocus,
          tint: crmLeadTone(l.status).colors(t).$1,
          kicker: 'crm.lead'.tr,
          title: l.contactName,
          subtitle: [?l.companyName, ?l.region].join(' · '),
          badge: OpsBadge(crmLeadStatusLabel(l.status), tone: crmLeadTone(l.status), large: true),
        ),
        CrmContactButtons(phone: l.phone, email: l.email),
        if (l.opportunityId != null) ...[
          VouchFlowPanel(
            padded: false,
            child: VouchFlowListRow(
              divider: false,
              icon: PhosphorIconsRegular.handshake,
              title: l.opportunityTitle ?? 'crm.opportunity'.tr,
              subtitle: 'crm.convertedTo'.trParams({'customer': l.customer ?? '-'}),
              trailing: Icon(PhosphorIconsBold.caretRight, size: 14, color: t.faint),
              onTap: () => Get.toNamed(Routes.crmOpportunity, arguments: l.opportunityId),
            ),
          ),
          erpGap,
        ],
        VouchFlowPanel(
          title: 'crm.details'.tr,
          child: Column(
            children: [
              ErpFact('crm.number'.tr, l.number),
              if (l.phone != null) ErpFact('crm.phone'.tr, l.phone!, onTap: () => crmContact('tel', l.phone!)),
              if (l.email != null) ErpFact('crm.emailField'.tr, l.email!, onTap: () => crmContact('mailto', l.email!)),
              ErpFact('crm.source'.tr, crmSourceLabel(l.source)),
              if (l.estimatedValue > 0) ErpFact('crm.estValue'.tr, crmMoney(l.estimatedValue, compact: false)),
              if (l.owner != null) ErpFact('crm.owner'.tr, l.owner!),
              if (l.createdAt != null) ErpFact('crm.created'.tr, dashDateTime(l.createdAt)),
              if (l.lostReason != null) ErpFact('crm.lostReason'.tr, l.lostReason!),
              if (l.notes != null) ErpFact('crm.notes'.tr, l.notes!),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'crm.activities'.tr,
          padded: false,
          child: l.activities.isEmpty
              ? OpsPanelEmpty('crm.noActivities'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < l.activities.length; i++)
                      CrmActivityRow(
                        activity: l.activities[i],
                        divider: i > 0,
                        showLink: false,
                        onDone: manage
                            ? () async {
                                if (await crmComplete(context, l.activities[i])) _load();
                              }
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

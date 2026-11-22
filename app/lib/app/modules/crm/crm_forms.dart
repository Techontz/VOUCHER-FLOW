import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/crm_repository.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDateTime;
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import 'crm_widgets.dart';

/// Adds a lead (POST /crm/leads): who, their business, how to reach them,
/// where they came from. Pops with the new lead's id.
class CrmLeadFormPage extends StatefulWidget {
  const CrmLeadFormPage({super.key});

  @override
  State<CrmLeadFormPage> createState() => _CrmLeadFormPageState();
}

class _CrmLeadFormPageState extends State<CrmLeadFormPage> {
  final _draft = CrmLeadDraft();
  bool _busy = false;
  ApiException? _error;

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      final lead = await CrmRepository.to.createLead(_draft);
      showToast('crm.leadAdded'.tr, body: lead.contactName);
      Get.back(result: lead.id);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = ApiException(0, 'state.offline'.tr); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VouchFlowPushedScaffold(
      title: 'crm.newLead'.tr,
      body: ErpGate(
        module: 'crm',
        permission: 'crm.manage',
        builder: (_) => ErpPageBody(
          children: [
            VouchFlowPanel(
              title: 'crm.contact'.tr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VouchFlowTextField(
                    label: 'crm.contactName'.tr,
                    required: true,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    error: _error?.field('contact_name'),
                    onChanged: (v) => setState(() => _draft.contactName = v),
                  ),
                  const SizedBox(height: 14),
                  VouchFlowTextField(
                    label: 'crm.business'.tr,
                    hint: 'inv.optional'.tr,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (v) => _draft.companyName = v,
                  ),
                  const SizedBox(height: 14),
                  VouchFlowTextField(
                    label: 'crm.phone'.tr,
                    keyboardType: TextInputType.phone,
                    error: _error?.field('phone'),
                    onChanged: (v) => _draft.phone = v,
                  ),
                  const SizedBox(height: 14),
                  VouchFlowTextField(
                    label: 'crm.emailField'.tr,
                    keyboardType: TextInputType.emailAddress,
                    error: _error?.field('email'),
                    onChanged: (v) => _draft.email = v,
                  ),
                  const SizedBox(height: 14),
                  VouchFlowTextField(label: 'crm.region'.tr, onChanged: (v) => _draft.region = v),
                ],
              ),
            ),
            erpGap,
            VouchFlowPanel(
              title: 'crm.details'.tr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VouchFlowDropdown<String>(
                    label: 'crm.source'.tr,
                    required: true,
                    items: CrmLeadStatus.sources,
                    value: _draft.source,
                    itemLabel: crmSourceLabel,
                    error: _error?.field('source'),
                    onChanged: (v) => setState(() => _draft.source = v ?? _draft.source),
                  ),
                  const SizedBox(height: 14),
                  VouchFlowTextField(
                    label: 'crm.estValue'.tr,
                    hint: 'inv.optional'.tr,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    onChanged: (v) => _draft.estimatedValue = v,
                  ),
                  const SizedBox(height: 14),
                  VouchFlowTextField(
                    label: 'crm.notes'.tr,
                    hint: 'inv.optional'.tr,
                    maxLines: 4,
                    minLines: 2,
                    onChanged: (v) => _draft.notes = v,
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              erpGap,
              VouchFlowAlert(message: _error!.message, tone: VfTone.bad, icon: PhosphorIconsRegular.warningCircle),
            ],
          ],
        ),
      ),
      bottomBar: OpsActionBar(
        children: [
          VouchFlowButton(
            label: 'crm.saveLead'.tr,
            icon: PhosphorIconsRegular.floppyDisk,
            expand: true,
            loading: _busy,
            onPressed: _busy || _draft.contactName.trim().isEmpty ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// Logs a call, meeting, visit or task (POST /crm/activities), linked to
/// the lead or deal it was opened from. "Already done" records it with its
/// outcome at once; otherwise it is a follow-up due when chosen. Arguments:
/// {'lead': id} or {'opportunity': id, 'customer': id}, plus 'name' to show.
class CrmActivityFormPage extends StatefulWidget {
  const CrmActivityFormPage({super.key});

  @override
  State<CrmActivityFormPage> createState() => _CrmActivityFormPageState();
}

class _CrmActivityFormPageState extends State<CrmActivityFormPage> {
  late final Map _args = (Get.arguments as Map?) ?? const {};
  late final _draft = CrmActivityDraft(
    leadId: _args['lead'] as int?,
    opportunityId: _args['opportunity'] as int?,
    customerId: _args['customer'] as int?,
  );
  bool _busy = false;
  ApiException? _error;

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _draft.due,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_draft.due));
    setState(() => _draft.due = DateTime(day.year, day.month, day.day, time?.hour ?? 9, time?.minute ?? 0));
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      await CrmRepository.to.log(_draft);
      showToast(_draft.done ? 'crm.logged'.tr : 'crm.scheduled'.tr, body: _draft.subject);
      Get.back(result: true);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = ApiException(0, 'state.offline'.tr); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final name = _args['name'] as String?;
    return VouchFlowPushedScaffold(
      title: 'crm.logActivity'.tr,
      body: ErpGate(
        module: 'crm',
        permission: 'crm.manage',
        builder: (_) => ErpPageBody(
          children: [
            if (name != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 14),
                child: Text('${'crm.linkedTo'.tr}: $name', style: VfType.small.copyWith(color: t.text2)),
              ),
            Row(
              children: [
                for (final type in CrmActivityType.all)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _TypeTile(
                        type: type,
                        selected: _draft.type == type,
                        onTap: () => setState(() => _draft.type = type),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            VouchFlowPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VouchFlowTextField(
                    label: 'crm.subject'.tr,
                    required: true,
                    placeholder: 'crm.subjectHint'.tr,
                    error: _error?.field('subject'),
                    onChanged: (v) => setState(() => _draft.subject = v),
                  ),
                  const SizedBox(height: 14),
                  VouchFlowTextField(
                    label: 'crm.notes'.tr,
                    hint: 'inv.optional'.tr,
                    maxLines: 5,
                    minLines: 2,
                    onChanged: (v) => _draft.notes = v,
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _draft.done,
                    onChanged: (v) => setState(() {
                      _draft.done = v;
                      if (v) _draft.due = DateTime.now();
                    }),
                    title: Text('crm.alreadyDone'.tr, style: VfType.label.copyWith(color: t.text)),
                    subtitle: Text(
                      _draft.done ? 'crm.alreadyDoneHint'.tr : 'crm.followUpHint'.tr,
                      style: VfType.meta.copyWith(color: t.muted),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_draft.done)
                    VouchFlowTextField(
                      label: 'crm.outcome'.tr,
                      hint: 'inv.optional'.tr,
                      placeholder: 'crm.outcomeHint'.tr,
                      onChanged: (v) => _draft.outcome = v,
                    )
                  else
                    VouchFlowTextField(
                      key: ValueKey(_draft.due),
                      label: 'crm.due'.tr,
                      readOnly: true,
                      initialValue: dashDateTime(_draft.due),
                      suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
                      error: _error?.field('due_at'),
                      onTap: _pickDue,
                    ),
                ],
              ),
            ),
            if (_error != null) ...[
              erpGap,
              VouchFlowAlert(message: _error!.message, tone: VfTone.bad, icon: PhosphorIconsRegular.warningCircle),
            ],
          ],
        ),
      ),
      bottomBar: OpsActionBar(
        children: [
          VouchFlowButton(
            label: _draft.done ? 'crm.saveLog'.tr : 'crm.schedule'.tr,
            icon: _draft.done ? PhosphorIconsRegular.checkCircle : PhosphorIconsRegular.calendarPlus,
            expand: true,
            loading: _busy,
            onPressed: _busy || _draft.subject.trim().isEmpty ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.type, required this.selected, required this.onTap});

  final String type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: vfCardDecoration(t).copyWith(
            color: selected ? t.primarySoftStrong : null,
            border: Border.all(color: selected ? t.primaryBorder : (t.isDark ? t.glassBorder : t.border), width: selected ? 1.5 : 1),
          ),
          child: Column(
            children: [
              Icon(crmActivityIcon(type), size: 22, color: selected ? t.primaryText : t.muted),
              const SizedBox(height: 4),
              Text(
                crmActivityLabel(type),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VfType.meta.copyWith(color: selected ? t.primaryText : t.text2, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

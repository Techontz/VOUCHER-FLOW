import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/services/template_repository.dart';
import '../../widgets/common.dart' show Fmt, showToast;
import '../../widgets/vf/vf.dart';
import '../admin/admin_widgets.dart' show adminReport, AdminNote, AdminSection;

/// A company's voucher design, and what may be done about it — the web's
/// VoucherTemplatePanel.
///
/// `company` mode is the tenant's own Branding page: the administrator may
/// change the design as many times as the platform allows (one), then asks
/// the platform. `platform` mode is the super admin's company page: any
/// design, any time, with a reason, and the full history. The server
/// enforces all of it; this only reflects what the server says is possible.
class VoucherTemplatePanel extends StatefulWidget {
  const VoucherTemplatePanel({
    super.key,
    required this.mode /* 'company' | 'platform' */,
    this.companyId,
    this.canManage = true,
    this.previews,
    this.previewsLoading = false,
    this.replacements = const {},
    this.onChanged,
  });

  /// 'company' or 'platform'.
  final String mode;

  /// The company, in platform mode.
  final int? companyId;

  /// Company mode: whether the viewer is the company administrator.
  final bool canManage;

  /// Sample documents keyed by design, in this company's letterhead. When
  /// omitted the panel asks the server for the company's own previews.
  final Map<String, String>? previews;
  final bool previewsLoading;

  /// Text swapped into every preview (a logo only the device holds).
  final Map<String, String> replacements;

  final ValueChanged<VoucherTemplateState>? onChanged;

  @override
  State<VoucherTemplatePanel> createState() => _VoucherTemplatePanelState();
}

class _VoucherTemplatePanelState extends State<VoucherTemplatePanel> {
  final _repo = TemplateRepository.to;

  VoucherTemplateState? _state;
  bool _loadError = false;
  Map<String, String> _ownPreviews = const {};
  bool _ownLoading = false;

  bool get _platform => widget.mode == 'platform';
  String get _locale => Get.locale?.languageCode ?? 'en';
  Map<String, String> get _previews => widget.previews ?? _ownPreviews;
  bool get _previewsLoading =>
      widget.previews != null ? widget.previewsLoading : _ownLoading;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.previews == null) _loadPreviews();
  }

  @override
  void didUpdateWidget(covariant VoucherTemplatePanel old) {
    super.didUpdateWidget(old);
    if (old.companyId != widget.companyId || old.mode != widget.mode) {
      _load();
      if (widget.previews == null) _loadPreviews();
    }
  }

  Future<void> _load() async {
    try {
      final s = _platform
          ? await _repo.platformState(widget.companyId!)
          : await _repo.companyState();
      if (!mounted) return;
      setState(() {
        _state = s;
        _loadError = s.templates.isEmpty;
      });
    } catch (_) {
      // Only a real template state is trusted; anything else (the offline
      // mock, an old server) reads as "designs unavailable".
      if (mounted) setState(() => _loadError = true);
    }
  }

  Future<void> _loadPreviews() async {
    setState(() => _ownLoading = true);
    try {
      final p = _platform
          ? await _repo.platformPreviews(widget.companyId!, locale: _locale)
          : await _repo.companyPreviews(locale: _locale);
      if (mounted) setState(() => _ownPreviews = p.html);
    } catch (_) {
      // The panel still works; thumbnails stay as placeholders.
    } finally {
      if (mounted) setState(() => _ownLoading = false);
    }
  }

  String _nameOf(String? key) {
    final t = _state?.templates.where((x) => x.key == key).firstOrNull;
    return t == null ? '—' : t.name(_locale);
  }

  String _numberOf(VoucherTemplate t) => t.number.toString().padLeft(2, '0');

  bool get _spent => (_state?.changesRemaining ?? 0) <= 0;
  bool get _mayChange => _platform || (widget.canManage && !_spent);

  String? get _chooseNote => !_platform && _mayChange
      ? 'branding.vt.chooseSubCompany'.tr
      : _platform
      ? 'branding.vt.chooseSubPlatform'.tr
      : null;

  /* ── flows ── */

  Future<void> _viewFullSize([String? key]) async {
    final s = _state!;
    final used = await showTemplatePreview(
      context,
      templates: s.templates,
      previews: _previews,
      initialKey: key ?? s.template,
      selected: s.template,
      canUse: _mayChange,
      useLabel: 'branding.vt.changeTo'.tr,
      note: _chooseNote,
      replacements: widget.replacements,
    );
    if (used != null && used != s.template && mounted) await _confirm(used);
  }

  Future<void> _choose() async {
    final s = _state!;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final t = ctx.vf;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * .92,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'branding.vt.chooseTitle'.tr,
                            style: VfType.sectionTitle.copyWith(color: t.text),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _platform
                                ? 'branding.vt.chooseSubPlatform'.tr
                                : 'branding.vt.chooseSubCompany'.tr,
                            style: VfType.small.copyWith(color: t.text2),
                          ),
                        ],
                      ),
                    ),
                    VouchFlowIconButton(
                      icon: PhosphorIconsRegular.x,
                      tooltip: 'branding.vt.cancel'.tr,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_previewsLoading && _previews.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'branding.preparing'.tr,
                      style: VfType.small.copyWith(color: t.muted),
                    ),
                  ),
                VouchFlowTemplateGallery(
                  templates: s.templates,
                  previews: _previews,
                  selected: null,
                  current: s.template,
                  replacements: widget.replacements,
                  onSelect: (key) {
                    if (key != s.template) Navigator.of(ctx).pop(key);
                  },
                  onPreview: (key) async {
                    final used = await showTemplatePreview(
                      ctx,
                      templates: s.templates,
                      previews: _previews,
                      initialKey: key,
                      selected: s.template,
                      canUse: _mayChange,
                      useLabel: 'branding.vt.changeTo'.tr,
                      note: _chooseNote,
                      replacements: widget.replacements,
                    );
                    if (used != null && used != s.template && ctx.mounted) {
                      Navigator.of(ctx).pop(used);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) await _confirm(picked);
  }

  Future<void> _confirm(String pending) async {
    final s = _state!;
    final reason = TextEditingController();
    var busy = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => VouchFlowDialog(
          icon: PhosphorIconsRegular.layout,
          tone: _platform ? VfTone.info : VfTone.warn,
          title: 'branding.vt.confirmTitle'.tr,
          subtitle: _platform
              ? 'branding.vt.confirmPlatform'.tr
              : 'branding.vt.confirmCompany'.tr,
          summary: [
            VfSummaryRow('branding.vt.from'.tr, _nameOf(s.template)),
            VfSummaryRow('branding.vt.to'.tr, _nameOf(pending)),
            if (!_platform)
              VfSummaryRow(
                'branding.vt.remaining'.tr,
                '${s.changesRemaining} → ${(s.changesRemaining - 1).clamp(0, 1 << 30)}',
              ),
          ],
          actions: [
            VouchFlowButton(
              label: 'branding.vt.cancel'.tr,
              variant: VfButtonVariant.secondary,
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
            ),
            VouchFlowButton(
              label: 'branding.vt.confirm'.tr,
              icon: PhosphorIconsBold.check,
              loading: busy,
              onPressed: busy
                  ? null
                  : () async {
                      setSheet(() => busy = true);
                      final ok = await _apply(pending, reason.text.trim());
                      if (!ctx.mounted) return;
                      if (ok) {
                        Navigator.of(ctx).pop();
                      } else {
                        setSheet(() => busy = false);
                      }
                    },
            ),
          ],
          child: VouchFlowTextField(
            label: 'branding.vt.optional'.tr,
            controller: reason,
            maxLength: 500,
            minLines: 3,
            maxLines: 5,
          ),
        ),
      ),
    );
    reason.dispose();
  }

  Future<bool> _apply(String template, String reason) async {
    try {
      final next = _platform
          ? await _repo.changePlatformTemplate(
              widget.companyId!,
              template,
              reason: reason.isEmpty ? null : reason,
            )
          : await _repo.changeCompanyTemplate(
              template,
              reason: reason.isEmpty ? null : reason,
            );
      if (!mounted) return true;
      setState(() => _state = next);
      widget.onChanged?.call(next);
      showToast('branding.vt.changed'.tr, body: _nameOf(template));
      return true;
    } catch (e) {
      adminReport(e, 'branding.vt.somethingWrong'.tr);
      _load();
      return false;
    }
  }

  Future<void> _request() async {
    final s = _state!;
    final options = s.templates.where((t) => t.key != s.template).toList();
    var wanted = options.firstOrNull?.key ?? '';
    final reason = TextEditingController();
    var busy = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => VouchFlowDialog(
          icon: PhosphorIconsRegular.paperPlaneTilt,
          tone: VfTone.primary,
          title: 'branding.vt.requestTitle'.tr,
          subtitle: 'branding.vt.requestSub'.tr,
          actions: [
            VouchFlowButton(
              label: 'branding.vt.cancel'.tr,
              variant: VfButtonVariant.secondary,
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
            ),
            VouchFlowButton(
              label: 'branding.vt.send'.tr,
              icon: PhosphorIconsRegular.paperPlaneTilt,
              loading: busy,
              onPressed: busy || wanted.isEmpty || reason.text.trim().length < 5
                  ? null
                  : () async {
                      setSheet(() => busy = true);
                      try {
                        await _repo.requestChange(wanted, reason.text.trim());
                        showToast('branding.vt.sent'.tr, body: _nameOf(wanted));
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (e) {
                        adminReport(e, 'branding.vt.somethingWrong'.tr);
                        if (ctx.mounted) setSheet(() => busy = false);
                      }
                    },
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VouchFlowDropdown<String>(
                label: 'branding.vt.wanted'.tr,
                items: [for (final t in options) t.key],
                value: wanted,
                itemLabel: (k) {
                  final t = options.firstWhere((x) => x.key == k);
                  return '${_numberOf(t)} · ${t.name(_locale)}';
                },
                onChanged: (v) => setSheet(() => wanted = v ?? wanted),
              ),
              const SizedBox(height: 12),
              VouchFlowTextField(
                label: 'branding.vt.reason'.tr,
                controller: reason,
                hint: 'branding.vt.reasonHint'.tr,
                maxLength: 500,
                minLines: 3,
                maxLines: 5,
                onChanged: (_) => setSheet(() {}),
              ),
            ],
          ),
        ),
      ),
    );
    reason.dispose();
  }

  /* ── build ── */

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    if (_loadError) {
      return AdminSection(
        label: 'branding.vt.title'.tr,
        child: AdminNote('branding.vt.unavailable'.tr),
      );
    }
    final s = _state;
    if (s == null) {
      return AdminSection(
        label: 'branding.vt.title'.tr,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final current = s.templates.where((x) => x.key == s.template).firstOrNull;
    final html = _previews[s.template];

    final thumb = Semantics(
      button: true,
      label: '${'branding.vt.view'.tr}: ${_nameOf(s.template)}',
      child: InkWell(
        onTap: () => _viewFullSize(),
        borderRadius: BorderRadius.circular(VfSize.radiusL),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: t.surface3,
            borderRadius: BorderRadius.circular(VfSize.radiusL),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: html == null
                ? AspectRatio(
                    aspectRatio: kA4Width / kA4Height,
                    child: ColoredBox(
                      color: t.surface2,
                      child: _previewsLoading
                          ? const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                  )
                : VouchFlowDocumentView(
                    html: html,
                    placeholderReplacements: widget.replacements,
                  ),
          ),
        ),
      ),
    );

    final locked = _spent && !_platform;
    final meter = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: locked ? t.warningSoft : t.surface3,
        borderRadius: BorderRadius.circular(VfSize.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            locked
                ? PhosphorIconsRegular.lockSimple
                : PhosphorIconsRegular.arrowsClockwise,
            size: 14,
            color: locked ? t.warningStrong : t.text2,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              _platform
                  ? TextSpan(
                      children: [
                        TextSpan(text: '${'branding.vt.used'.tr}: '),
                        TextSpan(
                          text: '${s.changesUsed} / ${s.changesAllowed}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' ${'branding.vt.usedSuffix'.tr}'),
                      ],
                    )
                  : TextSpan(
                      children: [
                        TextSpan(text: '${'branding.vt.remaining'.tr}: '),
                        TextSpan(
                          text: '${s.changesRemaining}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
              style: VfType.meta.copyWith(
                color: locked ? t.warningStrong : t.text2,
              ),
            ),
          ),
        ],
      ),
    );

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (current != null)
          Text(
            _numberOf(current),
            style: VfType.eyebrow.copyWith(color: t.primaryText, fontSize: 12),
          ),
        Text(
          _nameOf(s.template),
          style: VfType.cardTitle.copyWith(color: t.text, fontSize: 17),
        ),
        const SizedBox(height: 10),
        meter,
      ],
    );

    return AdminSection(
      label: 'branding.vt.title'.tr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 92, child: thumb),
              const SizedBox(width: 14),
              Expanded(child: summary),
            ],
          ),
          if (locked) ...[
            const SizedBox(height: 14),
            VouchFlowAlert(
              tone: VfTone.warn,
              icon: PhosphorIconsRegular.lockSimple,
              message: 'branding.vt.locked'.tr,
            ),
          ],
          if (!_platform && !widget.canManage && !_spent) ...[
            const SizedBox(height: 14),
            AdminNote('branding.vt.adminOnly'.tr),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: VouchFlowButton(
                  label: 'branding.vt.view'.tr,
                  icon: PhosphorIconsRegular.eye,
                  variant: VfButtonVariant.secondary,
                  compact: true,
                  onPressed: () => _viewFullSize(),
                ),
              ),
              if (_mayChange) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: VouchFlowButton(
                    label: 'branding.vt.change'.tr,
                    icon: PhosphorIconsRegular.layout,
                    compact: true,
                    onPressed: _choose,
                  ),
                ),
              ],
              if (!_platform && widget.canManage && _spent) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: VouchFlowButton(
                    label: 'branding.vt.request'.tr,
                    icon: PhosphorIconsRegular.paperPlaneTilt,
                    compact: true,
                    onPressed: _request,
                  ),
                ),
              ],
            ],
          ),
          if (_platform || s.history.isNotEmpty) ...[
            const SizedBox(height: 20),
            VouchFlowEyebrow('branding.vt.history'.tr),
            const SizedBox(height: 8),
            if (s.history.isEmpty)
              Text(
                'branding.vt.noHistory'.tr,
                style: VfType.small.copyWith(color: t.muted),
              )
            else
              for (final row in s.history)
                _HistoryRow(row: row, nameOf: _nameOf),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row, required this.nameOf});

  final VoucherTemplateChange row;
  final String Function(String?) nameOf;

  static const _sources = {
    'registration',
    'company_admin',
    'super_admin',
    'platform_create',
  };
  static const _roles = {'company_admin', 'super_admin'};

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final role = row.changedByRole;
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: VfType.meta.copyWith(color: t.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(value, style: VfType.small.copyWith(color: t.text2)),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 2,
            children: [
              Text(
                row.previousTemplate == null
                    ? '—'
                    : nameOf(row.previousTemplate),
                style: VfType.small.copyWith(color: t.text2),
              ),
              Icon(PhosphorIconsRegular.arrowRight, size: 14, color: t.muted),
              Text(
                nameOf(row.newTemplate),
                style: VfType.bodyStrong.copyWith(
                  color: t.text,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          line('branding.vt.by'.tr, row.changedByName ?? '—'),
          line(
            'branding.vt.role'.tr,
            role == null
                ? '—'
                : (_roles.contains(role) ? 'branding.vt.role.$role'.tr : role),
          ),
          line('branding.vt.date'.tr, Fmt.dateTime(row.createdAt?.toLocal())),
          line(
            'branding.vt.source'.tr,
            _sources.contains(row.source)
                ? 'branding.vt.src.${row.source}'.tr
                : row.source,
          ),
          line('branding.vt.reasonCol'.tr, row.reason ?? '—'),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/services/template_repository.dart';
import 'buttons.dart';
import 'documents.dart';

/// The ten voucher designs as real miniature vouchers — the web's template
/// gallery. On a phone the designs swipe sideways (as on the web under
/// 560px); on a tablet they sit two or three to a row.
class VouchFlowTemplateGallery extends StatelessWidget {
  const VouchFlowTemplateGallery({
    super.key,
    required this.templates,
    required this.previews,
    required this.selected,
    required this.onPreview,
    this.onSelect,
    this.current,
    this.replacements = const {},
  });

  final List<VoucherTemplate> templates;
  final Map<String, String> previews;
  final String? selected;
  final String? current;
  final ValueChanged<String> onPreview;
  final ValueChanged<String>? onSelect;
  final Map<String, String> replacements;

  @override
  Widget build(BuildContext context) {
    final locale = Get.locale?.languageCode ?? 'en';
    Widget card(VoucherTemplate t) => VouchFlowTemplateCard(
      number: t.number,
      name: t.name(locale),
      description: t.description(locale),
      html: previews[t.key],
      placeholderReplacements: replacements,
      selected: selected == t.key,
      isCurrent: current == t.key && selected != t.key,
      onPreview: () => onPreview(t.key),
      onSelect: onSelect == null ? null : () => onSelect!(t.key),
      previewLabel: 'common.preview'.tr,
      selectLabel: 'common.select'.tr,
      selectedLabel: 'common.selected'.tr,
      currentLabel: 'common.current'.tr,
    );

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 600) {
          final cols = box.maxWidth >= 900 ? 3 : 2;
          final w = (box.maxWidth - (cols - 1) * 16) / cols;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [for (final t in templates) SizedBox(width: w, child: card(t))],
          );
        }
        // Phone: a sideways row, each design ~78% of the width so the next
        // one peeks in and invites a swipe.
        final w = box.maxWidth * .78;
        return SizedBox(
          height: w * kA4Height / kA4Width + 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: templates.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(width: w, child: card(templates[i])),
          ),
        );
      },
    );
  }
}

/// One design at full size, with its neighbours a swipe away — the web's
/// template preview dialog. Returns the key the person chose to use, if any.
Future<String?> showTemplatePreview(
  BuildContext context, {
  required List<VoucherTemplate> templates,
  required Map<String, String> previews,
  required String initialKey,
  String? selected,
  bool canUse = true,
  String? useLabel,
  String? note,
  Map<String, String> replacements = const {},
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _TemplatePreviewPage(
        templates: templates,
        previews: previews,
        initialKey: initialKey,
        selected: selected,
        canUse: canUse,
        useLabel: useLabel,
        note: note,
        replacements: replacements,
      ),
    ),
  );
}

class _TemplatePreviewPage extends StatefulWidget {
  const _TemplatePreviewPage({
    required this.templates,
    required this.previews,
    required this.initialKey,
    required this.selected,
    required this.canUse,
    required this.useLabel,
    required this.note,
    required this.replacements,
  });

  final List<VoucherTemplate> templates;
  final Map<String, String> previews;
  final String initialKey;
  final String? selected;
  final bool canUse;
  final String? useLabel;
  final String? note;
  final Map<String, String> replacements;

  @override
  State<_TemplatePreviewPage> createState() => _TemplatePreviewPageState();
}

class _TemplatePreviewPageState extends State<_TemplatePreviewPage> {
  late int index = widget.templates.indexWhere((t) => t.key == widget.initialKey).clamp(0, widget.templates.length - 1);
  late final PageController _pages = PageController(initialPage: index);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _step(int d) {
    final n = (index + d + widget.templates.length) % widget.templates.length;
    _pages.animateToPage(n, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final locale = Get.locale?.languageCode ?? 'en';
    final tpl = widget.templates[index];
    final isSelected = widget.selected == tpl.key;

    return Scaffold(
      backgroundColor: t.surface3,
      appBar: AppBar(
        backgroundColor: t.surface,
        foregroundColor: t.text,
        toolbarHeight: 72,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${tpl.number.toString().padLeft(2, '0')} / ${widget.templates.length.toString().padLeft(2, '0')}',
              style: VfType.eyebrow.copyWith(fontSize: 11, color: t.muted),
            ),
            Text(tpl.name(locale), style: VfType.sectionTitle.copyWith(color: t.text)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'common.close'.tr,
            icon: Icon(PhosphorIconsRegular.x, color: t.text2),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: t.border)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text(tpl.description(locale), style: VfType.small.copyWith(color: t.muted)),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.templates.length,
              onPageChanged: (i) => setState(() => index = i),
              itemBuilder: (_, i) {
                final html = widget.previews[widget.templates[i].key];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 20, offset: const Offset(0, 8))],
                    ),
                    child: html == null
                        ? const Center(child: CircularProgressIndicator())
                        : VouchFlowDocumentView(
                            html: html,
                            fit: VfDocumentFit.fill,
                            interactive: true,
                            placeholderReplacements: widget.replacements,
                          ),
                  ),
                );
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(color: t.surface, border: Border(top: BorderSide(color: t.border))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.note != null) ...[
                      Text(widget.note!, style: VfType.meta.copyWith(color: t.muted, fontSize: 13)),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        VouchFlowIconButton(icon: PhosphorIconsRegular.caretLeft, tooltip: 'common.previous'.tr, onPressed: () => _step(-1)),
                        const SizedBox(width: 6),
                        VouchFlowIconButton(icon: PhosphorIconsRegular.caretRight, tooltip: 'common.next'.tr, onPressed: () => _step(1)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: widget.canUse
                              ? VouchFlowButton(
                                  label: isSelected ? 'common.selected'.tr : (widget.useLabel ?? 'common.useTemplate'.tr),
                                  icon: isSelected ? PhosphorIconsRegular.checkCircle : PhosphorIconsBold.check,
                                  onPressed: isSelected ? null : () => Navigator.of(context).pop(tpl.key),
                                )
                              : VouchFlowButton(
                                  label: 'common.close'.tr,
                                  variant: VfButtonVariant.secondary,
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

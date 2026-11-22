import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;

/*
 * Pieces the Inventory screens share: how a document type and status look
 * and read, a warehouse filter row, and the product picker.
 */

IconData docTypeIcon(String type) => switch (type) {
  ErpDocType.grn => PhosphorIconsRegular.trayArrowDown,
  ErpDocType.issue => PhosphorIconsRegular.trayArrowUp,
  ErpDocType.transfer => PhosphorIconsRegular.arrowsLeftRight,
  ErpDocType.adjustment => PhosphorIconsRegular.slidersHorizontal,
  ErpDocType.count => PhosphorIconsRegular.listNumbers,
  _ => PhosphorIconsRegular.flagBanner,
};

/// One quiet tint per kind of document, so a list scans by colour: in is
/// green, out is orange, a move is blue.
Color docTypeTint(VfTokens t, String type) => switch (type) {
  ErpDocType.grn => t.successStrong,
  ErpDocType.issue => t.warningStrong,
  ErpDocType.transfer => t.infoStrong,
  ErpDocType.opening => t.muted,
  _ => t.primary,
};

String docTypeLabel(String type) => 'inv.doc.$type'.tr;
String docTypeHint(String type) => 'inv.hint.$type'.tr;
String docStatusLabel(String status) => 'inv.status.$status'.tr;
String moveTypeLabel(String type) => 'inv.move.$type'.tr;
String productTypeLabel(String type) => 'inv.type.$type'.tr;

/// "3 lines" / "1 line".
String lineCountLabel(int n) => n == 1 ? 'inv.oneLine'.tr : 'inv.lineCount'.trParams({'n': '$n'});

/// A document's status as the web's DocStatus badge colours it.
class DocStatusBadge extends StatelessWidget {
  const DocStatusBadge(this.status, {super.key, this.large = false});

  final String status;
  final bool large;

  @override
  Widget build(BuildContext context) => VouchFlowStatusBadge(
    label: docStatusLabel(status),
    large: large,
    tag: switch (status) {
      ErpDocStatus.posted => 'tag-accent',
      ErpDocStatus.draft => 'tag-info',
      ErpDocStatus.reversed => 'tag-warn',
      _ => 'tag-neutral',
    },
  );
}

/// A document as one list row: its type, number, where and when, status.
class DocumentRow extends StatelessWidget {
  const DocumentRow({super.key, required this.doc, required this.onTap, this.divider = true});

  final ErpStockDocument doc;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowListRow(
      divider: divider,
      icon: docTypeIcon(doc.type),
      iconColor: docTypeTint(t, doc.type),
      title: docTypeLabel(doc.type),
      subtitle: [doc.number, doc.place, if (doc.documentDate != null) dashDate(doc.documentDate)]
          .where((s) => s.isNotEmpty)
          .join(' · '),
      trailing: DocStatusBadge(doc.status),
      onTap: onTap,
    );
  }
}

/// A quantity with its unit, right-aligned figures.
class QtyText extends StatelessWidget {
  const QtyText(this.value, {super.key, this.unit, this.style, this.signed = false});

  final num value;
  final String? unit;
  final TextStyle? style;

  /// Show + and - and colour in green and red (adjustments, variances).
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final base = (style ?? VfType.bodyStrong.copyWith(fontSize: 14.5)).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: signed ? (value > 0 ? t.successStrong : value < 0 ? t.dangerStrong : t.muted) : (style?.color ?? t.text),
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: signed ? ErpFmt.signed(value) : ErpFmt.qty(value), style: base),
          if (unit != null && unit!.isNotEmpty)
            TextSpan(
              text: ' $unit',
              style: VfType.meta.copyWith(color: t.muted, fontWeight: FontWeight.w500),
            ),
        ],
      ),
      maxLines: 1,
      textAlign: TextAlign.right,
    );
  }
}

/// "All warehouses", then one pill per warehouse, scrolling sideways.
class WarehouseFilter extends StatelessWidget {
  const WarehouseFilter({super.key, required this.warehouses, required this.selected, required this.onChanged});

  final List<ErpWarehouse> warehouses;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          VouchFlowFilterChip(label: 'inv.allWarehouses'.tr, selected: selected == null, onTap: () => onChanged(null)),
          for (final w in warehouses) ...[
            const SizedBox(width: 8),
            VouchFlowFilterChip(label: w.name, selected: selected == w.id, onTap: () => onChanged(w.id)),
          ],
        ],
      ),
    );
  }
}

/// Opens the product picker: a search over [products] (already loaded),
/// marking the ones in [added]. Returns the product chosen.
Future<ErpProduct?> pickProduct(
  BuildContext context, {
  required List<ErpProduct> products,
  Set<int> added = const {},
  String? title,
}) {
  return showVfSheet<ErpProduct>(
    context,
    builder: (ctx) => _ProductPicker(products: products, added: added, title: title ?? 'inv.pickProduct'.tr),
  );
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.products, required this.added, required this.title});

  final List<ErpProduct> products;
  final Set<int> added;
  final String title;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final q = _q.trim().toLowerCase();
    final rows = widget.products
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q) || (p.barcode ?? '') == q)
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(widget.title, style: VfType.sectionTitle.copyWith(color: t.text)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: VouchFlowSearchField(
                placeholder: 'inv.searchProducts'.tr,
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Flexible(
              child: rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text('inv.noProducts'.tr, textAlign: TextAlign.center, style: VfType.small.copyWith(color: t.muted)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final p = rows[i];
                        final added = widget.added.contains(p.id);
                        return VouchFlowListRow(
                          divider: i > 0,
                          icon: PhosphorIconsRegular.package,
                          title: p.name,
                          subtitle: [p.sku, if (p.unitCode.isNotEmpty) p.unitCode].join(' · '),
                          trailing: added
                              ? VouchFlowStatusBadge(label: 'inv.inDocument'.tr, tag: 'tag-info')
                              : Icon(PhosphorIconsBold.plus, size: 16, color: t.primaryText),
                          onTap: () => Navigator.of(context).pop(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled fact in a details card ("Prepared · Neema · 12 Nov 2026").
class ErpFact extends StatelessWidget {
  const ErpFact(this.label, this.value, {super.key, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: VfType.small.copyWith(color: t.muted)),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Text(
                value,
                style: VfType.small.copyWith(
                  color: onTap == null ? t.text : t.primaryText,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

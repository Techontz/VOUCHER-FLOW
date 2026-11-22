import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/ops_models.dart';
import '../../widgets/vf/vf.dart';
import '../erp/ops_kit.dart';

/*
 * Pieces the Documents screens share: a file's icon by its type, its size,
 * the expiry badge, and a document as a list row.
 */

String dmsTypeLabel(String type) => 'dms.type.$type'.tr;

IconData dmsFileIcon(String ext) => switch (ext) {
  'pdf' => PhosphorIconsRegular.filePdf,
  'jpg' || 'jpeg' || 'png' || 'webp' || 'gif' || 'heic' => PhosphorIconsRegular.fileImage,
  'doc' || 'docx' || 'odt' || 'rtf' => PhosphorIconsRegular.fileDoc,
  'xls' || 'xlsx' || 'ods' || 'csv' => PhosphorIconsRegular.fileXls,
  'ppt' || 'pptx' || 'odp' => PhosphorIconsRegular.filePpt,
  _ => PhosphorIconsRegular.fileText,
};

Color dmsFileTint(VfTokens t, String ext) => switch (ext) {
  'pdf' => t.dangerStrong,
  'jpg' || 'jpeg' || 'png' || 'webp' || 'gif' || 'heic' => t.infoStrong,
  'xls' || 'xlsx' || 'ods' || 'csv' => t.successStrong,
  'doc' || 'docx' || 'odt' || 'rtf' => t.primary,
  _ => t.muted,
};

String dmsSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(bytes < 10240 ? 1 : 0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// "12 days left", "Expires today", "Expired 5 days ago", or null.
/// [short] for a list row's badge ("Expired", "24 days").
({String label, VfTone tone})? dmsExpiry(DmsDocument d, {bool short = false}) {
  final days = d.daysToExpiry(DateTime.now());
  if (days == null) return null;
  if (days < 0) return (label: short ? 'dms.expired1'.tr : 'dms.expiredAgo'.trParams({'n': '${-days}'}), tone: VfTone.bad);
  if (days == 0) return (label: short ? 'dms.today'.tr : 'dms.expiresToday'.tr, tone: VfTone.bad);
  return (label: (short ? 'dms.daysShort' : 'dms.daysLeft').trParams({'n': '$days'}), tone: days <= 30 ? VfTone.warn : VfTone.neutral);
}

class DmsDocumentRow extends StatelessWidget {
  const DmsDocumentRow({super.key, required this.doc, required this.onTap, this.divider = true, this.showFolder = false});

  final DmsDocument doc;
  final VoidCallback onTap;
  final bool divider, showFolder;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final ext = doc.latest?.extension ?? '';
    final expiry = dmsExpiry(doc, short: true);
    final full = dmsExpiry(doc);
    return VouchFlowListRow(
      divider: divider,
      icon: dmsFileIcon(ext),
      iconColor: dmsFileTint(t, ext),
      title: doc.title,
      titleMaxLines: 2,
      subtitle: [
        dmsTypeLabel(doc.type),
        if (showFolder) ?doc.folder,
        if (expiry == null && doc.latest != null) dmsSize(doc.latest!.size),
        if (full != null) full.label,
      ].join(' · '),
      trailing: expiry == null ? null : OpsBadge(expiry.label, tone: expiry.tone),
      onTap: onTap,
    );
  }
}

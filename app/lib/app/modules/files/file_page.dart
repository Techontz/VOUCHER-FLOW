import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/files_repository.dart';
import '../../widgets/common.dart' show showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashDateTime;
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import '../inventory/inventory_widgets.dart' show ErpFact;
import 'files_widgets.dart';
import 'upload_page.dart' show pickDmsFile;

/// One document (the web's /erp/files/[id]): its details and expiry, the
/// versions, and Open, which fetches the file with the person's own
/// session (so the server logs it) and hands it to the phone's share sheet
/// to view, save or send. Opened with the document id.
class FilesDocumentPage extends StatefulWidget {
  const FilesDocumentPage({super.key, this.documentId});

  final int? documentId;

  @override
  State<FilesDocumentPage> createState() => _FilesDocumentPageState();
}

class _FilesDocumentPageState extends State<FilesDocumentPage> {
  late final int _id = widget.documentId ?? (Get.arguments as int);
  final _repo = FilesRepository.to;
  DmsDocument? _doc;
  String? _error;
  int? _opening;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    try {
      final d = await _repo.document(_id, refresh: refresh);
      if (mounted) setState(() { _doc = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = opsError(e));
    }
  }

  Future<void> _open(DmsDocument d, DmsVersion v) async {
    setState(() => _opening = v.version);
    try {
      final bytes = await _repo.download(d.id, version: v.version);
      await Share.shareXFiles(
        [XFile.fromData(Uint8List.fromList(bytes), name: v.name, mimeType: v.mime)],
        subject: d.title,
      );
    } catch (e) {
      showToast('dms.openFailed'.tr, body: opsError(e), kind: ToastKind.bad);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _newVersion(DmsDocument d) async {
    final file = await pickDmsFile(context);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      await _repo.addVersion(d.id, name: file.name, bytes: file.bytes);
      showToast('dms.versionAdded'.tr, body: file.name);
      await _load(refresh: true);
    } catch (e) {
      showToast('dms.uploadFailed'.tr, body: opsError(e), kind: ToastKind.bad);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _doc;
    final current = d?.versions.where((v) => v.version == d.currentVersion).firstOrNull ?? d?.latest;
    return VouchFlowPushedScaffold(
      title: d?.title ?? 'dms.document'.tr,
      body: d == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)]))
          : _body(context, d),
      bottomBar: d == null || current == null
          ? null
          : OpsActionBar(
              children: [
                if (d.canUpload)
                  VouchFlowButton(
                    label: 'dms.newVersion'.tr,
                    icon: PhosphorIconsRegular.uploadSimple,
                    variant: VfButtonVariant.secondary,
                    loading: _uploading,
                    onPressed: _uploading ? null : () => _newVersion(d),
                  ),
                VouchFlowButton(
                  label: 'dms.open'.tr,
                  icon: PhosphorIconsRegular.arrowSquareOut,
                  loading: _opening == current.version,
                  onPressed: _opening != null ? null : () => _open(d, current),
                ),
              ],
            ),
    );
  }

  Widget _body(BuildContext context, DmsDocument d) {
    final t = context.vf;
    final ext = d.latest?.extension ?? '';
    final expiry = dmsExpiry(d);
    return ErpPageBody(
      onRefresh: () => _load(refresh: true),
      children: [
        OpsHead(
          icon: dmsFileIcon(ext),
          tint: dmsFileTint(t, ext),
          kicker: dmsTypeLabel(d.type),
          title: d.title,
          subtitle: [
            if (d.breadcrumbs.isNotEmpty) d.breadcrumbs.map((b) => b.name).join(' / ') else 'dms.home'.tr,
            if (d.latest != null) dmsSize(d.latest!.size),
          ].join(' · '),
          badge: expiry == null ? null : OpsBadge(expiry.label, tone: expiry.tone, large: true),
        ),
        if (expiry != null && expiry.tone == VfTone.bad) ...[
          VouchFlowAlert(
            tone: VfTone.bad,
            icon: PhosphorIconsRegular.calendarX,
            message: (d.daysToExpiry(DateTime.now()) ?? 0) < 0
                ? 'dms.renewHint'.trParams({'date': dashDate(d.expiresOn)})
                : 'dms.renewToday'.tr,
          ),
          erpGap,
        ],
        VouchFlowPanel(
          title: 'dms.details'.tr,
          child: Column(
            children: [
              ErpFact('dms.typeField'.tr, dmsTypeLabel(d.type)),
              if (d.reference != null) ErpFact('inv.reference'.tr, d.reference!),
              if (d.issuedOn != null) ErpFact('dms.issued'.tr, dashDate(d.issuedOn)),
              if (d.expiresOn != null) ErpFact('dms.expires'.tr, dashDate(d.expiresOn)),
              if (d.tags.isNotEmpty) ErpFact('dms.tags'.tr, d.tags.join(', ')),
              if (d.owner != null) ErpFact('dms.owner'.tr, d.owner!),
              if (d.createdAt != null) ErpFact('dms.uploaded'.tr, dashDateTime(d.createdAt)),
              if (d.retained) ErpFact('dms.retention'.tr, d.retainUntil == null ? 'dms.retained'.tr : '${'dms.retainUntil'.tr} ${dashDate(d.retainUntil)}'),
              if (d.description != null) ErpFact('dms.description'.tr, d.description!),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'dms.versions'.tr,
          padded: false,
          child: Column(
            children: [
              for (var i = 0; i < d.versions.length; i++)
                VouchFlowListRow(
                  divider: i > 0,
                  icon: dmsFileIcon(d.versions[i].extension),
                  iconColor: dmsFileTint(t, d.versions[i].extension),
                  title: 'dms.versionN'.trParams({'n': '${d.versions[i].version}'}),
                  subtitle: [
                    d.versions[i].name,
                    dmsSize(d.versions[i].size),
                    ?d.versions[i].uploader,
                    if (d.versions[i].at != null) dashDate(d.versions[i].at),
                    ?d.versions[i].note,
                  ].join(' · '),
                  trailing: _opening == d.versions[i].version
                      ? const VfLoader(size: 22)
                      : d.versions[i].version == d.currentVersion
                      ? OpsBadge('dms.current'.tr, tone: VfTone.ok)
                      : Icon(PhosphorIconsRegular.arrowSquareOut, size: 18, color: t.primaryText),
                  onTap: _opening != null ? null : () => _open(d, d.versions[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

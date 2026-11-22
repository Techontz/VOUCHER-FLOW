import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/files_repository.dart';
import '../../widgets/common.dart' show showToast, ToastKind;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import 'files_widgets.dart';

/// A file chosen on the phone.
typedef DmsPicked = ({String name, List<int> bytes});

/// Asks where the file comes from (camera, photos, files), picks it and
/// checks the server's rules (type, 20 MB) first. Null when cancelled or
/// refused, with the reason shown.
Future<DmsPicked?> pickDmsFile(BuildContext context) async {
  final source = await showVouchFlowBottomSheet<String>(
    context,
    title: 'dms.pickFrom'.tr,
    child: Column(
      children: [
        for (final (key, icon) in [
          ('camera', PhosphorIconsRegular.camera),
          ('gallery', PhosphorIconsRegular.image),
          ('files', PhosphorIconsRegular.folderOpen),
        ])
          Builder(
            builder: (ctx) => VouchFlowListRow(
              divider: key != 'camera',
              icon: icon,
              title: 'dms.from.$key'.tr,
              onTap: () => Navigator.of(ctx).pop(key),
            ),
          ),
        const SizedBox(height: 16),
      ],
    ),
  );
  if (source == null) return null;
  DmsPicked? file;
  try {
    if (source == 'files') {
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: DmsType.extensions, withData: true);
      final f = r?.files.firstOrNull;
      if (f?.bytes != null) file = (name: f!.name, bytes: f.bytes!);
    } else {
      final x = await ImagePicker().pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (x != null) file = (name: x.name, bytes: await x.readAsBytes());
    }
  } catch (_) {
    return null;
  }
  if (file == null) return null;
  final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
  if (!DmsType.extensions.contains(ext)) {
    showToast('dms.uploadFailed'.tr, body: 'dms.wrongType'.trParams({'name': file.name}), kind: ToastKind.bad);
    return null;
  }
  if (file.bytes.length > DmsType.maxBytes) {
    showToast('dms.uploadFailed'.tr, body: 'dms.tooBig'.trParams({'name': file.name}), kind: ToastKind.bad);
    return null;
  }
  return file;
}

/// Uploads a document from the phone (POST /files/documents): the file from
/// the camera, photos or files, then its title, folder, type, reference,
/// dates and tags. Arguments: {'folder': id} to start in a folder. Pops
/// with the new document's id.
class FilesUploadPage extends StatefulWidget {
  const FilesUploadPage({super.key});

  @override
  State<FilesUploadPage> createState() => _FilesUploadPageState();
}

class _FilesUploadPageState extends State<FilesUploadPage> {
  final _repo = FilesRepository.to;
  late final _draft = DmsUploadDraft()..folderId = (Get.arguments as Map?)?['folder'] as int?;
  List<DmsFolder>? _folders;
  DmsPicked? _file;
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _repo.folders().then((f) {
      if (mounted) setState(() => _folders = f);
    }).catchError((_) {
      if (mounted) setState(() => _folders = const []);
    });
  }

  Future<void> _pick() async {
    final f = await pickDmsFile(context);
    if (f == null) return;
    setState(() {
      _file = f;
      if (_draft.title.trim().isEmpty) {
        final base = f.name.contains('.') ? f.name.substring(0, f.name.lastIndexOf('.')) : f.name;
        _draft.title = base.replaceAll(RegExp(r'[-_]+'), ' ');
      }
    });
  }

  Future<void> _date(bool expiry) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (expiry ? _draft.expiresOn : _draft.issuedOn) ?? now,
      firstDate: DateTime(now.year - 30),
      lastDate: DateTime(now.year + 30),
    );
    if (picked == null) return;
    setState(() => expiry ? _draft.expiresOn = picked : _draft.issuedOn = picked);
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      final doc = await _repo.upload(_draft, name: f.name, bytes: f.bytes);
      showToast('dms.uploadedOne'.tr, body: doc.title);
      Get.back(result: doc.id);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = ApiException(0, 'state.offline'.tr); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VouchFlowPushedScaffold(
      title: 'dms.upload'.tr,
      body: ErpGate(module: 'documents', permission: 'documents.upload', builder: _form),
      bottomBar: OpsActionBar(
        children: [
          VouchFlowButton(
            label: 'dms.upload'.tr,
            icon: PhosphorIconsRegular.uploadSimple,
            expand: true,
            loading: _busy,
            onPressed: _busy || _file == null ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final t = context.vf;
    final f = _file;
    final ext = f == null || !f.name.contains('.') ? '' : f.name.split('.').last.toLowerCase();
    final folders = _folders ?? const <DmsFolder>[];
    Widget dateField(String label, DateTime? value, bool expiry) => Expanded(
      child: VouchFlowTextField(
        key: ValueKey((label, value)),
        label: label,
        hint: 'inv.optional'.tr,
        readOnly: true,
        initialValue: value == null ? '' : dashDate(value),
        error: _error?.field(expiry ? 'expires_on' : 'issued_on'),
        suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
        onTap: () => _date(expiry),
      ),
    );

    return ErpPageBody(
      children: [
        Semantics(
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(VfSize.radiusL),
            onTap: _busy ? null : _pick,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: vfCardDecoration(t),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: (f == null ? t.primary : dmsFileTint(t, ext)).withValues(alpha: t.isDark ? .18 : .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      f == null ? PhosphorIconsRegular.uploadSimple : dmsFileIcon(ext),
                      size: 25,
                      color: f == null ? t.primary : dmsFileTint(t, ext),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f?.name ?? 'dms.chooseFile'.tr,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: VfType.bodyStrong.copyWith(color: t.text, height: 1.3),
                        ),
                        Text(
                          f == null ? 'dms.dropHint'.tr : '${dmsSize(f.bytes.length)} · ${'dms.tapToChange'.tr}',
                          style: VfType.meta.copyWith(color: t.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_error?.field('file') case final e?) ...[
          const SizedBox(height: 6),
          Text(e, style: VfType.small.copyWith(color: t.dangerStrong)),
        ],
        erpGap,
        VouchFlowPanel(
          title: 'dms.details'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VouchFlowTextField(
                key: ValueKey(('title', f?.name)),
                label: 'dms.titleField'.tr,
                initialValue: _draft.title,
                maxLength: 180,
                error: _error?.field('title'),
                onChanged: (v) => _draft.title = v,
              ),
              const SizedBox(height: 14),
              VouchFlowDropdown<int?>(
                label: 'dms.folder'.tr,
                items: [null, for (final x in folders) x.id],
                value: _draft.folderId,
                itemLabel: (id) => id == null ? 'dms.home'.tr : folders.firstWhere((x) => x.id == id).name,
                error: _error?.field('folder_id'),
                onChanged: (v) => setState(() => _draft.folderId = v),
              ),
              const SizedBox(height: 14),
              VouchFlowDropdown<String>(
                label: 'dms.typeField'.tr,
                items: DmsType.all,
                value: _draft.type,
                itemLabel: dmsTypeLabel,
                onChanged: (v) => setState(() => _draft.type = v ?? 'general'),
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(label: 'inv.reference'.tr, hint: 'inv.optional'.tr, maxLength: 80, onChanged: (v) => _draft.reference = v),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  dateField('dms.issued'.tr, _draft.issuedOn, false),
                  const SizedBox(width: 10),
                  dateField('dms.expires'.tr, _draft.expiresOn, true),
                ],
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: 'dms.tags'.tr,
                hint: 'dms.tagsHint'.tr,
                onChanged: (v) => _draft.tags = v,
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                label: 'dms.description'.tr,
                hint: 'inv.optional'.tr,
                maxLines: 4,
                minLines: 2,
                onChanged: (v) => _draft.description = v,
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          erpGap,
          VouchFlowAlert(message: _error!.message, tone: VfTone.bad, icon: PhosphorIconsRegular.warningCircle),
        ],
      ],
    );
  }
}

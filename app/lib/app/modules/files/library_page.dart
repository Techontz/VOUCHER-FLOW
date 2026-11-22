import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/ops_models.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/files_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import 'files_widgets.dart';

/// The library (the web's /erp/files): one folder at a time with the path
/// back up, its sub-folders and documents; typing searches every document
/// the person may open, narrowed by type. Upload drops into the open folder.
class FilesLibraryPage extends StatelessWidget {
  const FilesLibraryPage({super.key});

  @override
  Widget build(BuildContext context) =>
      ErpGate(module: 'documents', permission: 'documents.view', builder: (_) => const _Library());
}

class _Library extends StatefulWidget {
  const _Library();

  @override
  State<_Library> createState() => _LibraryState();
}

class _LibraryState extends State<_Library> {
  final _repo = FilesRepository.to;
  int? _folderId;
  DmsListing? _listing;
  String? _error;
  int _generation = 0;

  String _q = '';
  String? _type;
  Timer? _debounce;
  List<DmsDocument>? _results;

  bool get _searching => _q.trim().isNotEmpty || _type != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      if (_searching) {
        final page = await _repo.search(q: _q.trim().isEmpty ? null : _q.trim(), type: _type);
        if (mounted && generation == _generation) setState(() { _results = page.data; _error = null; });
      } else {
        final l = await _repo.browse(folderId: _folderId);
        if (mounted && generation == _generation) setState(() { _listing = l; _error = null; });
      }
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = opsError(e));
    }
  }

  void _search(String v) {
    _q = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      setState(() => _results = null);
      _load();
    });
  }

  void _into(int? folder) {
    setState(() { _folderId = folder; _listing = null; });
    _load();
  }

  Future<void> _open(DmsDocument d) async {
    await Get.toNamed(Routes.filesDocument, arguments: d.id);
    _load();
  }

  Future<void> _upload() async {
    final id = await Get.toNamed(Routes.filesUpload, arguments: {'folder': _folderId});
    if (id is int) {
      await Get.toNamed(Routes.filesDocument, arguments: id);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final canUpload = ErpService.to.can('documents.upload');
    final l = _listing;
    return PopScope(
      canPop: _folderId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _into(l?.folder?.parentId);
      },
      child: ErpPageBody(
        onRefresh: _load,
        children: [
          ErpPageTitle(
            'dms.title'.tr,
            subtitle: 'dms.sub'.tr,
            trailing: canUpload
                ? VouchFlowButton(label: 'dms.upload'.tr, icon: PhosphorIconsBold.uploadSimple, compact: true, onPressed: _upload)
                : null,
          ),
          VouchFlowSearchField(placeholder: 'dms.search'.tr, onChanged: _search),
          const SizedBox(height: 10),
          OpsChips<String?>(
            values: const [null, ...DmsType.all],
            selected: _type,
            label: (s) => s == null ? 'dms.allTypes'.tr : dmsTypeLabel(s),
            onChanged: (s) {
              setState(() { _type = s; _results = null; });
              _load();
            },
          ),
          const SizedBox(height: 14),
          if (_searching) ..._searchResults(t) else ..._folder(t, l),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  List<Widget> _searchResults(VfTokens t) {
    final rows = _results;
    if (rows == null) {
      return [
        _error == null
            ? const VfLoadingView(inline: true)
            : VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr),
      ];
    }
    if (rows.isEmpty) return [VouchFlowEmptyState(icon: PhosphorIconsRegular.magnifyingGlass, title: 'dms.noResults'.tr)];
    return [
      VouchFlowPanel(
        padded: false,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              DmsDocumentRow(doc: rows[i], divider: i > 0, showFolder: true, onTap: () => _open(rows[i])),
          ],
        ),
      ),
    ];
  }

  List<Widget> _folder(VfTokens t, DmsListing? l) {
    if (l == null) {
      return [
        _error == null
            ? const VfLoadingView(inline: true)
            : VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr),
      ];
    }
    final crumbs = [ErpRef(0, 'dms.home'.tr), ...l.breadcrumbs];
    return [
      if (_folderId != null) ...[
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: crumbs.length,
            separatorBuilder: (_, _) => Icon(PhosphorIconsBold.caretRight, size: 12, color: t.faint),
            itemBuilder: (_, i) {
              final last = i == crumbs.length - 1;
              return TextButton(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 34)),
                onPressed: last ? null : () => _into(crumbs[i].id == 0 ? null : crumbs[i].id),
                child: Text(
                  crumbs[i].name,
                  style: VfType.small.copyWith(color: last ? t.text : t.primaryText, fontWeight: last ? FontWeight.w600 : FontWeight.w500),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
      if (l.folders.isNotEmpty) ...[
        VouchFlowPanel(
          title: 'dms.folders'.tr,
          padded: false,
          child: Column(
            children: [
              for (var i = 0; i < l.folders.length; i++)
                VouchFlowListRow(
                  divider: i > 0,
                  icon: PhosphorIconsFill.folderSimple,
                  iconColor: t.warningStrong,
                  title: l.folders[i].name,
                  subtitle: [
                    'dms.docsN'.trParams({'n': '${l.folders[i].documents}'}),
                    ?l.folders[i].description,
                  ].join(' · '),
                  trailing: Icon(PhosphorIconsBold.caretRight, size: 14, color: t.faint),
                  onTap: () => _into(l.folders[i].id),
                ),
            ],
          ),
        ),
        erpGap,
      ],
      if (l.documents.isNotEmpty)
        VouchFlowPanel(
          title: 'dms.documents'.tr,
          padded: false,
          child: Column(
            children: [
              for (var i = 0; i < l.documents.length; i++)
                DmsDocumentRow(doc: l.documents[i], divider: i > 0, onTap: () => _open(l.documents[i])),
            ],
          ),
        )
      else if (l.folders.isEmpty)
        VouchFlowEmptyState(icon: PhosphorIconsRegular.folderOpen, title: 'dms.emptyFolder'.tr),
    ];
  }
}

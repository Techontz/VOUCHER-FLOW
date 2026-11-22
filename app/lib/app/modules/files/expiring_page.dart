import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/models/ops_models.dart';
import '../../data/services/files_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';
import '../erp/ops_kit.dart';
import 'files_widgets.dart';

/// Licences, permits, certificates and policies that expire soon, and
/// those already expired (the web's /erp/files/expiring), soonest first.
class FilesExpiringPage extends StatelessWidget {
  const FilesExpiringPage({super.key});

  @override
  Widget build(BuildContext context) =>
      ErpGate(module: 'documents', permission: 'documents.view', builder: (_) => const _Expiring());
}

class _Expiring extends StatefulWidget {
  const _Expiring();

  @override
  State<_Expiring> createState() => _ExpiringState();
}

class _ExpiringState extends State<_Expiring> {
  int _days = 30;
  List<DmsDocument>? _rows;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final rows = await FilesRepository.to.expiring(days: _days);
      if (mounted && generation == _generation) setState(() { _rows = rows; _error = null; });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = opsError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final now = DateTime.now();
    final expired = rows?.where((d) => (d.daysToExpiry(now) ?? 1) < 0).toList() ?? const [];
    final soon = rows?.where((d) => (d.daysToExpiry(now) ?? -1) >= 0).toList() ?? const [];

    Widget panel(String title, List<DmsDocument> docs) => VouchFlowPanel(
      title: title,
      trailing: Text('${docs.length}'),
      padded: false,
      child: Column(
        children: [
          for (var i = 0; i < docs.length; i++)
            DmsDocumentRow(
              doc: docs[i],
              divider: i > 0,
              showFolder: true,
              onTap: () async {
                await Get.toNamed(Routes.filesDocument, arguments: docs[i].id);
                _load();
              },
            ),
        ],
      ),
    );

    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('dms.nav.expiring'.tr, subtitle: 'dms.expiringSub'.tr),
        OpsChips<int>(
          values: const [30, 60, 90, 180],
          selected: _days,
          label: (d) => 'dms.withinDays'.trParams({'n': '$d'}),
          onChanged: (d) {
            setState(() { _days = d; _rows = null; });
            _load();
          },
        ),
        const SizedBox(height: 14),
        if (rows == null)
          _error == null
              ? const VfLoadingView(inline: true)
              : VouchFlowErrorState(message: _error!, onRetry: _load, retryLabel: 'action.retry'.tr)
        else if (rows.isEmpty)
          VouchFlowEmptyState(icon: PhosphorIconsRegular.calendarCheck, title: 'dms.nothingExpiring'.tr)
        else ...[
          if (expired.isNotEmpty) ...[panel('dms.expired'.tr, expired), erpGap],
          if (soon.isNotEmpty) panel('dms.expiringSoon'.tr, soon),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/inventory_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashIsSw;
import '../erp/erp_widgets.dart';
import 'inventory_app.dart';
import 'inventory_widgets.dart';

/// The Inventory home: the four figures that matter (stock value, low
/// stock, drafts to post, products), what you can prepare, the week's
/// movements and the latest documents (the web's /erp page).
class InventoryOverviewPage extends StatelessWidget {
  const InventoryOverviewPage({super.key});

  @override
  Widget build(BuildContext context) => ErpGate(
    module: 'inventory',
    permission: 'inventory.view',
    builder: (_) => const _Overview(),
  );
}

class _Overview extends StatefulWidget {
  const _Overview();

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  final _repo = InventoryRepository.to;
  final _erp = ErpService.to;
  InventoryOverview? _data;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _repo.overview();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'state.offline'.tr;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _open(int id) async {
    await Get.toNamed(Routes.erpDocument, arguments: id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const VfLoadingView();
    if (_error != null && _data == null) {
      return ErpPageBody(
        onRefresh: _load,
        children: [
          VouchFlowErrorState(
            message: _error!,
            onRetry: _load,
            retryLabel: 'action.retry'.tr,
          ),
        ],
      );
    }
    final inv = _data;
    final config = _erp.config.value;
    final currency = _erp.currency;
    final actions = inventoryCreateActions
        .where((a) => a.permission == null || _erp.can(a.permission!))
        .toList();

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 600;
        final figures = inv == null
            ? const <Widget>[]
            : [
                VouchFlowFigureGrid(
                  children: [
                    VouchFlowFigureCard(
                      label: 'inv.stockValue'.tr,
                      value: ErpFmt.compactMoney(inv.stockValue, currency),
                      hint:
                          '$currency ${ErpFmt.amount(inv.stockValue.round())}',
                      icon: PhosphorIconsRegular.coins,
                      onTap: () => erpGo('/erp/stock'),
                    ),
                    VouchFlowFigureCard(
                      label: 'inv.lowStock'.tr,
                      value: '${inv.lowStock}',
                      hint: inv.lowStock > 0
                          ? 'inv.lowStockHint'.tr
                          : 'inv.lowStockNone'.tr,
                      icon: PhosphorIconsRegular.warning,
                      tone: inv.lowStock > 0 ? VfTone.warn : VfTone.ok,
                      onTap: () => erpGo('/erp/stock'),
                    ),
                    VouchFlowFigureCard(
                      label: 'inv.drafts'.tr,
                      value: '${inv.drafts}',
                      hint: inv.drafts > 0
                          ? 'inv.draftsHint'.tr
                          : 'inv.draftsNone'.tr,
                      icon: PhosphorIconsRegular.fileDashed,
                      tone: inv.drafts > 0 ? VfTone.info : VfTone.neutral,
                      onTap: () => erpGo('/erp/documents'),
                    ),
                    VouchFlowFigureCard(
                      label: 'inv.products'.tr,
                      value: '${inv.products}',
                      hint: 'inv.productsHint'.trParams({
                        'n': '${inv.warehouses}',
                      }),
                      icon: PhosphorIconsRegular.package,
                      tone: VfTone.neutral,
                    ),
                  ],
                ),
              ];

        return ErpPageBody(
          onRefresh: _load,
          children: [
            ErpPageTitle('area.inventory'.tr, subtitle: config?.businessLabel),
            if (wide)
              _Grid(children: figures)
            else
              for (final f in figures) ...[f, const SizedBox(height: 12)],
            if (wide) erpGap else const SizedBox(height: 2),
            if (actions.isNotEmpty) ...[
              VouchFlowPanel(
                title: 'inv.quickActions'.tr,
                padded: false,
                child: Column(
                  children: [
                    for (var i = 0; i < actions.length; i++)
                      VouchFlowListRow(
                        divider: i > 0,
                        icon: actions[i].icon,
                        title: actions[i].label.tr,
                        subtitle: actions[i].hint?.tr,
                        trailing: Icon(
                          PhosphorIconsBold.caretRight,
                          size: 14,
                          color: context.vf.faint,
                        ),
                        onTap: () async {
                          await erpCreate(actions[i]);
                          _load();
                        },
                      ),
                  ],
                ),
              ),
              erpGap,
            ],
            if (inv != null) ...[
              VouchFlowPanel(
                title: 'inv.movementsWeek'.tr,
                subtitle: 'inv.movementsCount'.trParams({
                  'n': '${inv.movements7d.values.fold(0, (a, b) => a + b)}',
                }),
                child: _WeekBars(inv.movements7d),
              ),
              erpGap,
              VouchFlowPanel(
                title: 'inv.recentDocuments'.tr,
                padded: false,
                actionLabel: 'erp.viewAll'.tr,
                onAction: () => erpGo('/erp/documents'),
                child: inv.recent.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(22),
                        child: Text(
                          'inv.noDocuments'.tr,
                          textAlign: TextAlign.center,
                          style: VfType.small.copyWith(color: context.vf.muted),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < inv.recent.length; i++)
                            DocumentRow(
                              doc: inv.recent[i],
                              divider: i > 0,
                              onTap: () => _open(inv.recent[i].id),
                            ),
                        ],
                      ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Two figure cards per row on a tablet.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Seven columns ending today, today in the accent colour (the web's
/// erp-bars).
class _WeekBars extends StatelessWidget {
  const _WeekBars(this.counts);

  final Map<String, int> counts;

  static const _en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _sw = ['Jtt', 'Jnn', 'Jtn', 'Alh', 'Iju', 'Jms', 'Jpl'];

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final now = DateTime.now();
    final days = [
      for (var i = 6; i >= 0; i--)
        DateTime(now.year, now.month, now.day).subtract(Duration(days: i)),
    ];
    String key(DateTime d) =>
        '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';
    final values = [for (final d in days) counts[key(d)] ?? 0];
    final peak = values.fold(1, (a, b) => a > b ? a : b);
    final names = dashIsSw ? _sw : _en;

    return Semantics(
      label: [
        for (var i = 0; i < 7; i++)
          '${names[days[i].weekday - 1]}: ${values[i]}',
      ].join(', '),
      child: ExcludeSemantics(
        child: SizedBox(
          height: 132,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          values[i] > 0 ? '${values[i]}' : '',
                          style: VfType.meta.copyWith(
                            fontSize: 11.5,
                            color: t.muted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: values[i] == 0
                                  ? .04
                                  : (values[i] / peak).clamp(.08, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: i == 6
                                      ? t.primary
                                      : t.primary.withValues(
                                          alpha: t.isDark ? .35 : .22,
                                        ),
                                  borderRadius: BorderRadius.circular(
                                    VfSize.radiusS,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          names[days[i].weekday - 1],
                          style: VfType.meta.copyWith(
                            fontSize: 11.5,
                            color: i == 6 ? t.text : t.muted,
                            fontWeight: i == 6
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

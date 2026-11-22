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
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import 'inventory_widgets.dart';

/// One product: how much is held and what it is worth, where it is held
/// (per warehouse and batch) and its latest movements (the web's
/// /erp/products/[id]). Opened with the product id as the argument.
class ProductPage extends StatefulWidget {
  const ProductPage({super.key, this.productId});

  final int? productId;

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  late final int _id = widget.productId ?? (Get.arguments as int);
  ErpProductDetail? _p;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await InventoryRepository.to.product(_id);
      if (mounted) {
        setState(() {
          _p = p;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'state.offline'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return VouchFlowPushedScaffold(
      title: p?.product.name ?? 'inv.nav.stock'.tr,
      body: p == null
          ? (_error == null
                ? const VfLoadingView()
                : ErpPageBody(
                    children: [
                      VouchFlowErrorState(
                        message: _error!,
                        onRetry: _load,
                        retryLabel: 'action.retry'.tr,
                      ),
                    ],
                  ))
          : _body(context, p),
    );
  }

  Widget _body(BuildContext context, ErpProductDetail d) {
    final p = d.product;
    final currency = ErpService.to.currency;
    final low = p.reorderLevel > 0 && d.onHand <= p.reorderLevel;
    final tracking = [
      if (p.trackBatches) 'inv.batch'.tr,
      if (p.trackExpiry) 'inv.expiry'.tr,
    ].join(' · ');

    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle(
          p.name,
          subtitle: [
            p.sku,
            productTypeLabel(p.type),
            ?p.category?.name,
          ].join(' · '),
        ),
        VouchFlowFigureGrid(
          children: [
            VouchFlowFigureCard(
              label: 'inv.onHand'.tr,
              value: '${ErpFmt.qty(d.onHand)} ${p.unitCode}'.trim(),
              hint: p.reorderLevel > 0
                  ? 'inv.reorderAt'.trParams({'n': ErpFmt.qty(p.reorderLevel)})
                  : null,
              icon: PhosphorIconsRegular.stack,
              tone: low ? VfTone.warn : VfTone.primary,
            ),
            VouchFlowFigureCard(
              label: 'inv.stockValue'.tr,
              value: ErpFmt.compactMoney(d.stockValue, currency),
              hint: '$currency ${ErpFmt.amount(d.stockValue.round())}',
              icon: PhosphorIconsRegular.coins,
              tone: VfTone.neutral,
            ),
          ],
        ),
        erpGap,
        VouchFlowPanel(
          title: 'inv.details'.tr,
          child: Column(
            children: [
              ErpFact(
                'inv.costPrice'.tr,
                '$currency ${ErpFmt.amount(p.costPrice)}',
              ),
              if (p.salePrice > 0)
                ErpFact(
                  'inv.salePrice'.tr,
                  '$currency ${ErpFmt.amount(p.salePrice)}',
                ),
              ErpFact(
                'inv.reorderLevel'.tr,
                '${ErpFmt.qty(p.reorderLevel)} ${p.unitCode}'.trim(),
              ),
              if (tracking.isNotEmpty) ErpFact('inv.tracking'.tr, tracking),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'inv.whereHeld'.tr,
          padded: false,
          child: d.balances.isEmpty
              ? _quiet(context, 'inv.noBalances'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < d.balances.length; i++)
                      VouchFlowListRow(
                        divider: i > 0,
                        icon: PhosphorIconsRegular.warehouse,
                        title: d.balances[i].warehouse?.name ?? '',
                        subtitle: [
                          if (d.balances[i].batchNumber.isNotEmpty)
                            d.balances[i].batchNumber,
                          if (d.balances[i].expiryDate != null)
                            'inv.expiresOn'.trParams({
                              'date': dashDate(d.balances[i].expiryDate),
                            }),
                          '${'inv.avgCost'.tr} ${ErpFmt.amount(d.balances[i].averageCost)}',
                        ].join(' · '),
                        trailing: QtyText(
                          d.balances[i].quantity,
                          unit: p.unitCode,
                        ),
                      ),
                  ],
                ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'inv.recentMovements'.tr,
          padded: false,
          child: d.movements.isEmpty
              ? _quiet(context, 'inv.noMovements'.tr)
              : Column(
                  children: [
                    for (var i = 0; i < d.movements.length; i++)
                      MovementRow(
                        movement: d.movements[i],
                        divider: i > 0,
                        unit: p.unitCode,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _quiet(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.all(20),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: VfType.small.copyWith(color: context.vf.muted),
    ),
  );
}

/// One posted movement: what it was, its document, where and when, and the
/// signed quantity with the balance it left.
class MovementRow extends StatelessWidget {
  const MovementRow({
    super.key,
    required this.movement,
    this.divider = true,
    this.unit,
    this.showProduct = false,
  });

  final ErpStockMovement movement;
  final bool divider;
  final String? unit;
  final bool showProduct;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final m = movement;
    final inbound = m.quantity >= 0;
    return VouchFlowListRow(
      divider: divider,
      icon: inbound
          ? PhosphorIconsRegular.arrowDownLeft
          : PhosphorIconsRegular.arrowUpRight,
      iconColor: inbound ? t.successStrong : t.warningStrong,
      title: showProduct && m.productName != null
          ? m.productName!
          : moveTypeLabel(m.type),
      subtitle: [
        if (showProduct) moveTypeLabel(m.type),
        m.reference,
        m.warehouse?.name ?? '',
        if (m.movementDate != null) dashDate(m.movementDate),
      ].where((s) => s.isNotEmpty).join(' · '),
      onTap: m.documentId == null
          ? null
          : () => Get.toNamed(
              Routes.erpDocument,
              arguments: m.documentId,
              preventDuplicates: false,
            ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          QtyText(m.quantity, unit: unit, signed: true),
          const SizedBox(height: 2),
          Text(
            '= ${ErpFmt.qty(m.balanceAfter)}',
            style: VfType.meta.copyWith(
              color: t.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

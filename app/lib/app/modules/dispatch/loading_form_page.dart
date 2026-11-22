import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/models/sales_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/sales_repository.dart';
import '../../routes/routes.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import '../sales/sales_widgets.dart';

/// Plans a truck for an approved order (the web's "Create loading order"
/// dialog): which warehouse, when, the vehicle and driver, and how much of
/// what is left goes on this truck. Opened with {'orderId': int?}; without
/// one it first asks which released order to load.
class LoadingFormPage extends StatefulWidget {
  const LoadingFormPage({super.key, this.orderId});

  final int? orderId;

  @override
  State<LoadingFormPage> createState() => _LoadingFormPageState();
}

class _LoadingFormPageState extends State<LoadingFormPage> {
  late int? _orderId = widget.orderId ?? (Get.arguments is Map ? (Get.arguments as Map)['orderId'] as int? : null);
  final _repo = SalesRepository.to;

  DispatchLookups? _lookups;
  SalesOrder? _order;
  String? _loadError;
  int? _warehouseId;
  DateTime _date = DateTime.now();
  final _vehicle = TextEditingController();
  final _driver = TextEditingController();
  final _destination = TextEditingController();
  final _qty = <int, TextEditingController>{};
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _vehicle.dispose();
    _driver.dispose();
    _destination.dispose();
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      if (_orderId == null) {
        final l = await _repo.dispatchLookups();
        if (mounted) setState(() => _lookups = l);
        return;
      }
      final o = await _repo.order(_orderId!);
      if (!mounted) return;
      setState(() {
        _order = o;
        _warehouseId = o.warehouseId ?? o.warehouses.firstOrNull?.id;
        _destination.text = o.deliveryAddress ?? '';
        for (final c in _qty.values) {
          c.dispose();
        }
        _qty
          ..clear()
          ..addAll({
            for (final e in o.remainingToLoad.entries)
              if (e.value > 0) e.key: TextEditingController(text: ErpFmt.qty(e.value).replaceAll(',', '')),
          });
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'state.offline'.tr);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1));
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final o = _order;
    if (o == null || _warehouseId == null) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      final loading = await _repo.createLoading(
        salesOrderId: o.id,
        warehouseId: _warehouseId!,
        plannedDate: _date,
        vehicleNumber: _vehicle.text,
        driverName: _driver.text,
        destination: _destination.text,
        quantities: {for (final e in _qty.entries) e.key: salesNum(e.value.text)},
      );
      showToast('dsp.loadingCreated'.tr, body: loading.number);
      Get.offNamed(Routes.dispatchLoading, arguments: loading.id);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = ApiException(0, 'state.offline'.tr); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VouchFlowPushedScaffold(
      title: 'dsp.newLoading'.tr,
      body: ErpGate(
        module: 'dispatch',
        permission: 'dispatch.load',
        builder: (context) {
          if (_loadError != null) {
            return ErpPageBody(children: [VouchFlowErrorState(message: _loadError!, onRetry: _load, retryLabel: 'action.retry'.tr)]);
          }
          if (_orderId == null) return _lookups == null ? const VfLoadingView() : _choose(context, _lookups!);
          return _order == null ? const VfLoadingView() : _form(context, _order!);
        },
      ),
      bottomBar: _order == null
          ? null
          : SalesActionBar(
              children: [
                VouchFlowButton(
                  label: 'dsp.createLoading'.tr,
                  icon: PhosphorIconsRegular.truck,
                  expand: true,
                  loading: _busy,
                  onPressed: _busy || _warehouseId == null || _qty.isEmpty ? null : _save,
                ),
              ],
            ),
    );
  }

  Widget _choose(BuildContext context, DispatchLookups l) {
    final t = context.vf;
    return ErpPageBody(
      onRefresh: _load,
      children: [
        ErpPageTitle('dsp.whichOrder'.tr, subtitle: 'dsp.whichOrderSub'.tr),
        if (l.readyOrders.isEmpty)
          VouchFlowEmptyState(icon: PhosphorIconsRegular.checkCircle, title: 'dsp.noneReady'.tr)
        else
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < l.readyOrders.length; i++)
                  VouchFlowListRow(
                    divider: i > 0,
                    icon: PhosphorIconsRegular.shoppingCart,
                    iconColor: t.successStrong,
                    title: l.readyOrders[i].customer?.name ?? l.readyOrders[i].number,
                    subtitle: [l.readyOrders[i].number, ?l.readyOrders[i].deliveryAddress].join(' · '),
                    trailing: SalesStatusBadge(l.readyOrders[i].status),
                    onTap: () {
                      setState(() => _orderId = l.readyOrders[i].id);
                      _load();
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _form(BuildContext context, SalesOrder o) {
    final t = context.vf;
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final lines = o.lines.where((l) => _qty.containsKey(l.id)).toList();
    return ErpPageBody(
      children: [
        SalesDocHead(
          icon: PhosphorIconsRegular.shoppingCart,
          tint: t.successStrong,
          kind: 'sal.order'.tr,
          number: o.number,
          status: o.status,
          subtitle: o.customer?.name,
        ),
        if (lines.isEmpty)
          VouchFlowAlert(message: 'dsp.nothingLeft'.tr, tone: VfTone.info, icon: PhosphorIconsRegular.info)
        else ...[
          VouchFlowPanel(
            title: 'dsp.truck'.tr,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VouchFlowDropdown<int>(
                  label: 'sal.warehouse'.tr,
                  required: true,
                  items: [for (final w in o.warehouses) w.id],
                  value: _warehouseId,
                  itemLabel: (id) => o.warehouses.firstWhere((w) => w.id == id).name,
                  error: _error?.field('warehouse_id'),
                  onChanged: (v) => setState(() => _warehouseId = v),
                ),
                const SizedBox(height: 14),
                VouchFlowTextField(
                  key: ValueKey(_date),
                  label: 'dsp.planned'.tr,
                  readOnly: true,
                  initialValue: dashDate(_date),
                  suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 14),
                VouchFlowTextField(
                  label: 'dsp.vehicle'.tr,
                  hint: 'sal.optional'.tr,
                  placeholder: 'T 123 ABC',
                  controller: _vehicle,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 40,
                ),
                const SizedBox(height: 14),
                VouchFlowTextField(label: 'dsp.driver'.tr, hint: 'sal.optional'.tr, controller: _driver, maxLength: 120),
                const SizedBox(height: 14),
                VouchFlowTextField(label: 'dsp.destination'.tr, hint: 'sal.optional'.tr, controller: _destination, maxLength: 255),
              ],
            ),
          ),
          erpGap,
          VouchFlowPanel(
            title: 'dsp.onThisTruck'.tr,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final l in lines)
                  VouchFlowTextField(
                    label: l.productName,
                    hint: [
                      'dsp.leftToLoad'.trParams({'n': ErpFmt.qty(o.remainingToLoad[l.id] ?? 0)}),
                      'dsp.availableHere'.trParams({
                        'n': ErpFmt.qty(o.availability[l.productId]?[_warehouseId]?.available ?? 0),
                      }),
                    ].join(' · '),
                    controller: _qty[l.id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: numbers,
                  ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          erpGap,
          VouchFlowAlert(message: _error!.message, tone: VfTone.bad, icon: PhosphorIconsRegular.warningCircle),
        ],
      ],
    );
  }
}

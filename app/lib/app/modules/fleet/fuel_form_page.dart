import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart' show ErpFmt, ErpPage;
import '../../data/models/fleet_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/fleet_repository.dart';
import '../../widgets/common.dart' show showToast;
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;
import '../erp/erp_widgets.dart';
import 'fleet_widgets.dart';

/// Logs fuel on a trip: the trip, litres and price (the amount follows),
/// the odometer, station and receipt, and how it was paid, exactly what
/// TripController@fuelRules takes. A driver's entry waits for someone with
/// fleet.approve; staff with that permission record it approved.
///
/// Opened with {'mine': bool, 'tripId': int?}. Closes with `true` once saved.
class FuelFormPage extends StatefulWidget {
  const FuelFormPage({super.key, this.mine, this.tripId});

  final bool? mine;
  final int? tripId;

  @override
  State<FuelFormPage> createState() => _FuelFormPageState();
}

class _FuelFormPageState extends State<FuelFormPage> {
  late final Map? _args = Get.arguments is Map ? Get.arguments as Map : null;
  late final bool _mine = widget.mine ?? (_args?['mine'] != false);
  late int? _tripId = widget.tripId ?? _args?['tripId'] as int?;

  final _repo = FleetRepository.to;
  final _erp = ErpService.to;
  final _draft = FuelDraft();

  List<FleetTrip>? _trips;
  FleetPayLookups? _pay;
  String? _loadError;
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final results = await Future.wait([
        _repo.trips(mine: _mine),
        _repo.payLookups(mine: _mine),
      ]);
      final trips = (results[0] as ErpPage<FleetTrip>).data;
      final pay = results[1] as FleetPayLookups;
      // Fuel goes on trips the company pays for that are not closed;
      // the one on the road first.
      final open = trips.where((t) => t.takesFuel).toList()
        ..sort((a, b) => _rank(a).compareTo(_rank(b)));
      if (!mounted) return;
      setState(() {
        _trips = open;
        _pay = pay;
        if (_tripId == null || !open.any((t) => t.id == _tripId)) _tripId = open.firstOrNull?.id;
        _draft.accountId ??= pay.accounts.firstOrNull?.id;
        _draft.supplierId ??= _suppliers(pay).firstOrNull?.id;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'state.offline'.tr);
    }
  }

  static int _rank(FleetTrip t) => switch (t.status) {
    FleetTripStatus.dispatched => 0,
    FleetTripStatus.planned => 1,
    _ => 2,
  };

  /// Fuel stations first.
  List<FleetPick> _suppliers(FleetPayLookups pay) =>
      [...pay.suppliers]..sort((a, b) => (a.category == 'Fuel' ? 0 : 1).compareTo(b.category == 'Fuel' ? 0 : 1));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.date,
      firstDate: now.subtract(const Duration(days: 60)),
      lastDate: now,
    );
    if (picked != null) setState(() => _draft.date = picked);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final trip = _tripId;
    if (trip == null) {
      setState(() => _error = ApiException(422, 'flt.pickTrip'.tr));
      return;
    }
    if ((_draft.litresValue ?? 0) <= 0 || (_draft.priceValue ?? 0) <= 0) {
      setState(() => _error = ApiException(422, 'flt.enterLitres'.tr));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await _repo.recordFuel(trip, _draft, mine: _mine);
      // Back first: a toast shown before would be what Get.back closes.
      Get.back(result: true);
      showToast('flt.fuelSaved'.tr, body: message.isEmpty ? null : message);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e; });
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = ApiException(0, 'state.offline'.tr); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _trips != null && _pay != null;
    return VouchFlowPushedScaffold(
      title: _mine ? 'flt.logFuel'.tr : 'flt.recordFuel'.tr,
      body: ErpGate(
        module: 'fleet',
        permission: _mine ? 'fleet.own' : 'fleet.fuel',
        builder: (context) {
          if (!ready) {
            return _loadError == null
                ? const VfLoadingView()
                : ErpPageBody(children: [VouchFlowErrorState(message: _loadError!, onRetry: _load, retryLabel: 'action.retry'.tr)]);
          }
          if (_trips!.isEmpty) {
            return ErpEmpty(icon: PhosphorIconsRegular.path, title: 'flt.noOpenTrip'.tr, body: 'flt.noOpenTripBody'.tr);
          }
          return _form(context);
        },
      ),
      bottomBar: !ready || _trips!.isEmpty
          ? null
          : BottomActionBar(
              children: [
                VouchFlowButton(
                  label: 'flt.saveFuel'.tr,
                  icon: PhosphorIconsRegular.check,
                  expand: true,
                  height: 54,
                  loading: _busy,
                  onPressed: _busy ? null : _save,
                ),
              ],
            ),
    );
  }

  Widget _form(BuildContext context) {
    final t = context.vf;
    final trips = _trips!;
    final pay = _pay!;
    final currency = _erp.currency;
    final numbers = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    final suppliers = _suppliers(pay);

    return ErpPageBody(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: t.infoStrong.withValues(alpha: t.isDark ? .18 : .12), borderRadius: BorderRadius.circular(12)),
                child: Icon(PhosphorIconsRegular.gasPump, size: 24, color: t.infoStrong),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _mine && !_erp.can('fleet.approve') ? 'flt.fuelHintDriver'.tr : 'flt.fuelHint'.tr,
                  style: VfType.small.copyWith(color: t.text2),
                ),
              ),
            ],
          ),
        ),
        VouchFlowPanel(
          title: 'flt.trip'.tr,
          child: VouchFlowDropdown<int>(
            label: 'flt.whichTrip'.tr,
            required: true,
            items: [for (final trip in trips) trip.id],
            value: _tripId,
            itemLabel: (id) {
              final trip = trips.firstWhere((x) => x.id == id);
              return '${trip.route} · ${trip.number}';
            },
            error: _error?.field('trip_id'),
            onChanged: (v) => setState(() => _tripId = v),
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'flt.howMuch'.tr,
          trailing: _draft.amount > 0
              ? Text(
                  '$currency ${ErpFmt.amount(double.parse(_draft.amount.toStringAsFixed(2)))}',
                  style: VfType.small.copyWith(color: t.text, fontWeight: FontWeight.w700),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: VouchFlowTextField(
                      key: const ValueKey('fuel-litres'),
                      label: 'flt.litres'.tr,
                      required: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: numbers,
                      suffix: Text('L', style: VfType.label.copyWith(color: t.muted)),
                      error: _error?.field('litres'),
                      onChanged: (v) => setState(() => _draft.litres = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: VouchFlowTextField(
                      key: const ValueKey('fuel-price'),
                      label: 'flt.pricePerLitre'.tr,
                      required: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: numbers,
                      error: _error?.field('price_per_litre'),
                      onChanged: (v) => setState(() => _draft.price = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                key: const ValueKey('fuel-odometer'),
                label: 'flt.odometer'.tr,
                hint: 'flt.odometerHint'.tr,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: numbers,
                suffix: Text('km', style: VfType.label.copyWith(color: t.muted)),
                error: _error?.field('odometer'),
                onChanged: (v) => _draft.odometer = v,
              ),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'flt.whereWhen'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VouchFlowTextField(
                key: const ValueKey('fuel-station'),
                label: 'flt.station'.tr,
                placeholder: 'flt.stationHint'.tr,
                maxLength: 120,
                textCapitalization: TextCapitalization.words,
                onChanged: (v) => _draft.station = v,
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                key: const ValueKey('fuel-receipt'),
                label: 'flt.receipt'.tr,
                hint: 'flt.optional'.tr,
                maxLength: 60,
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) => _draft.receipt = v,
              ),
              const SizedBox(height: 14),
              VouchFlowTextField(
                key: ValueKey(_draft.date),
                label: 'flt.date'.tr,
                readOnly: true,
                initialValue: dashDate(_draft.date),
                suffix: Icon(PhosphorIconsRegular.calendarBlank, size: 18, color: t.muted),
                error: _error?.field('issue_date'),
                onTap: _pickDate,
              ),
            ],
          ),
        ),
        erpGap,
        VouchFlowPanel(
          title: 'flt.paidHow'.tr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  VouchFlowFilterChip(
                    label: 'flt.paidCash'.tr,
                    selected: _draft.paidBy == 'account',
                    onTap: () => setState(() => _draft.paidBy = 'account'),
                  ),
                  if (suppliers.isNotEmpty)
                    VouchFlowFilterChip(
                      label: 'flt.paidCredit'.tr,
                      selected: _draft.paidBy == 'supplier',
                      onTap: () => setState(() => _draft.paidBy = 'supplier'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (_draft.paidBy == 'account')
                VouchFlowDropdown<int>(
                  label: 'flt.cashAccount'.tr,
                  required: true,
                  items: [for (final a in pay.accounts) a.id],
                  value: _draft.accountId,
                  itemLabel: (id) => pay.accounts.firstWhere((a) => a.id == id).label,
                  error: _error?.field('account_id'),
                  onChanged: (v) => setState(() => _draft.accountId = v),
                )
              else
                VouchFlowDropdown<int>(
                  label: 'flt.supplier'.tr,
                  required: true,
                  items: [for (final s in suppliers) s.id],
                  value: _draft.supplierId,
                  itemLabel: (id) => suppliers.firstWhere((s) => s.id == id).name,
                  error: _error?.field('supplier_id'),
                  onChanged: (v) => setState(() => _draft.supplierId = v),
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

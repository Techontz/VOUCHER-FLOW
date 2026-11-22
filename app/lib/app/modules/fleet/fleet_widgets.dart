import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart' show ErpFmt;
import '../../data/models/fleet_models.dart';
import '../../data/models/people_json.dart';
import '../../data/services/api_service.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate;

/*
 * Pieces the Fleet screens share: how a trip, a vehicle, a fuel entry and a
 * service read (label, badge colour, one list row each), and how a paper's
 * expiry is worded.
 */

String tripStatusLabel(String s) => 'flt.trip.$s'.tr;
String vehicleStatusLabel(String s) => 'flt.vehicle.$s'.tr;
String entryStatusLabel(String s) => 'flt.entry.$s'.tr;

/// "152,492 km".
String kmLabel(num? v) => v == null ? '-' : '${ErpFmt.qty(v.round())} km';

/// "180 L".
String litresLabel(num v) => '${ErpFmt.qty(v)} L';

class TripStatusBadge extends StatelessWidget {
  const TripStatusBadge(this.status, {super.key, this.large = false});

  final String status;
  final bool large;

  @override
  Widget build(BuildContext context) => VouchFlowStatusBadge(
    label: tripStatusLabel(status),
    large: large,
    tag: switch (status) {
      FleetTripStatus.planned => 'tag-info',
      FleetTripStatus.dispatched => 'tag-warn',
      FleetTripStatus.completed => 'tag-accent',
      FleetTripStatus.cancelled => 'tag-accent-2',
      _ => 'tag-neutral',
    },
  );
}

class VehicleStatusBadge extends StatelessWidget {
  const VehicleStatusBadge(this.status, {super.key, this.large = false});

  final String status;
  final bool large;

  @override
  Widget build(BuildContext context) => VouchFlowStatusBadge(
    label: vehicleStatusLabel(status),
    large: large,
    tag: switch (status) {
      FleetVehicleStatus.available => 'tag-accent',
      FleetVehicleStatus.onTrip => 'tag-info',
      FleetVehicleStatus.maintenance => 'tag-warn',
      _ => 'tag-accent-2',
    },
  );
}

class EntryStatusBadge extends StatelessWidget {
  const EntryStatusBadge(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) => VouchFlowStatusBadge(
    label: entryStatusLabel(status),
    tag: switch (status) {
      FleetEntryStatus.approved => 'tag-accent',
      FleetEntryStatus.rejected => 'tag-accent-2',
      _ => 'tag-warn',
    },
  );
}

/// Due-state of a maintenance schedule.
class DueBadge extends StatelessWidget {
  const DueBadge(this.state, {super.key});

  final String state;

  @override
  Widget build(BuildContext context) => VouchFlowStatusBadge(
    label: 'flt.due.$state'.tr,
    tag: switch (state) {
      'overdue' => 'tag-accent-2',
      'due' => 'tag-warn',
      _ => 'tag-accent',
    },
  );
}

/// One trip in a list: the route, its number, vehicle and day, its status.
class TripRow extends StatelessWidget {
  const TripRow({super.key, required this.trip, required this.onTap, this.divider = true, this.showDriver = true});

  final FleetTrip trip;
  final VoidCallback onTap;
  final bool divider, showDriver;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final when = trip.actualStart ?? trip.plannedStart;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.path,
      iconColor: trip.status == FleetTripStatus.dispatched ? t.warningStrong : t.primary,
      title: trip.route,
      subtitle: [
        trip.number,
        if (trip.vehicleLabel.isNotEmpty) trip.vehicleLabel,
        if (showDriver && trip.driver != null) trip.driver!,
        if (when != null) dashDate(when),
      ].join(' · '),
      trailing: TripStatusBadge(trip.status),
      onTap: onTap,
    );
  }
}

/// One fuel entry: litres and amount, where and on which trip, its state.
class FuelRow extends StatelessWidget {
  const FuelRow({super.key, required this.fuel, required this.currency, this.onTap, this.divider = true, this.showTrip = true});

  final FleetFuel fuel;
  final String currency;
  final VoidCallback? onTap;
  final bool divider, showTrip;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.gasPump,
      iconColor: fuel.isPending ? t.warningStrong : t.infoStrong,
      title: '${litresLabel(fuel.litres)} · $currency ${ErpFmt.amount(fuel.amount)}',
      subtitle: [
        ?fuel.station,
        if (showTrip) ?(fuel.tripNumber ?? fuel.vehicle),
        if (fuel.issueDate != null) dashDate(fuel.issueDate),
      ].join(' · '),
      trailing: EntryStatusBadge(fuel.status),
      onTap: onTap,
    );
  }
}

/// A schedule as a row: what, which vehicle, when or at what reading.
class ScheduleRow extends StatelessWidget {
  const ScheduleRow({super.key, required this.schedule, this.onTap, this.divider = true, this.showVehicle = true});

  final FleetSchedule schedule;
  final VoidCallback? onTap;
  final bool divider, showVehicle;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final s = schedule;
    final next = [
      if (s.nextDueDate != null) dashDate(s.nextDueDate),
      if (s.nextDueOdometer != null) kmLabel(s.nextDueOdometer),
    ].join(' / ');
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.wrench,
      iconColor: switch (s.state) {
        'overdue' => t.dangerStrong,
        'due' => t.warningStrong,
        _ => t.successStrong,
      },
      title: s.title,
      subtitle: [
        if (showVehicle) ?s.vehicle,
        if (next.isNotEmpty) '${'flt.nextDue'.tr} $next',
      ].join(' · '),
      trailing: DueBadge(s.state),
      onTap: onTap,
    );
  }
}

/// How long a paper has left, worded and toned: "Expires in 14 days",
/// "Expired 3 days ago".
(String, VfTone) expiryWords(DateTime? date) {
  if (date == null) return ('flt.noDate'.tr, VfTone.neutral);
  final n = daysUntil(date);
  if (n < 0) return ('flt.expiredAgo'.trParams({'n': '${-n}'}), VfTone.bad);
  if (n == 0) return ('flt.expiresToday'.tr, VfTone.bad);
  if (n <= 30) return ('flt.expiresIn'.trParams({'n': '$n'}), VfTone.warn);
  return ('flt.validTo'.trParams({'date': dashDate(date)}), VfTone.ok);
}

/// A paper (insurance, road licence, driving licence) and its expiry.
class PaperRow extends StatelessWidget {
  const PaperRow({super.key, required this.label, required this.date, this.number, this.divider = true, this.onTap});

  final String label;
  final DateTime? date;
  final String? number;
  final bool divider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final (words, tone) = expiryWords(date);
    final (fg, _) = tone.colors(t);
    return VouchFlowListRow(
      divider: divider,
      icon: PhosphorIconsRegular.certificate,
      iconColor: tone == VfTone.ok ? t.successStrong : fg,
      title: label,
      subtitle: [?number, if (date != null) dashDate(date)].join(' · '),
      trailing: Text(
        words,
        textAlign: TextAlign.right,
        style: VfType.meta.copyWith(color: tone == VfTone.ok ? t.muted : fg, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}

/// A big, quiet empty line inside a panel.
class PanelEmpty extends StatelessWidget {
  const PanelEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(22),
    child: Text(text, textAlign: TextAlign.center, style: VfType.small.copyWith(color: context.vf.muted)),
  );
}

/// A labelled fact for detail cards.
class FactLine extends StatelessWidget {
  const FactLine(this.label, this.value, {super.key, this.strong = false, this.alignEnd = false});

  final String label;
  final String value;
  final bool strong;

  /// Figures in a column, right-aligned (a payslip).
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alignEnd)
            Expanded(child: Text(label, style: VfType.small.copyWith(color: strong ? t.text : t.muted, fontWeight: strong ? FontWeight.w600 : null)))
          else
            SizedBox(width: 124, child: Text(label, style: VfType.small.copyWith(color: t.muted))),
          if (alignEnd) const SizedBox(width: 12),
          Expanded(
            flex: alignEnd ? 0 : 1,
            child: Text(
              value,
              textAlign: alignEnd ? TextAlign.right : TextAlign.start,
              style: VfType.small.copyWith(
                color: t.text,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tinted icon tile and title block at the head of a detail page.
class DetailHead extends StatelessWidget {
  const DetailHead({super.key, required this.icon, required this.tint, required this.eyebrow, required this.title, this.subtitle, this.badge});

  final IconData icon;
  final Color tint;
  final String eyebrow, title;
  final String? subtitle;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: tint.withValues(alpha: t.isDark ? .18 : .12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 25, color: tint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow, style: VfType.small.copyWith(color: t.muted, fontWeight: FontWeight.w500)),
                Text(
                  title,
                  style: VfType.pageTitle.copyWith(color: t.text, fontSize: 19, letterSpacing: -.3),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: VfType.small.copyWith(color: t.text2)),
                ],
                if (badge != null) ...[const SizedBox(height: 10), badge!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width bar at the foot of a pushed page, for its main action.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VfGlass(
      borderRadius: BorderRadius.zero,
      fill: t.barFill,
      highlight: false,
      shadow: false,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(VfSize.pagePad, 12, VfSize.pagePad, 12),
          child: children.length == 1 ? children.single : VouchFlowActions(children: children),
        ),
      ),
    );
  }
}

/// Pills that filter a list by status, scrolling sideways.
class StatusFilter extends StatelessWidget {
  const StatusFilter({super.key, required this.values, required this.selected, required this.label, required this.onChanged});

  final List<String?> values;
  final String? selected;
  final String Function(String?) label;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final v in values) ...[
          VouchFlowFilterChip(label: label(v), selected: selected == v, onTap: () => onChanged(v)),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

/// The two buttons at the foot of a confirmation sheet, with an optional
/// field (an odometer reading, a reason); the confirming one runs [run] and
/// closes the sheet with its result, or shows the API's refusal in place.
class ConfirmActions extends StatefulWidget {
  const ConfirmActions({
    super.key,
    required this.confirmLabel,
    required this.run,
    this.backLabel,
    this.danger = false,
    this.fieldLabel,
    this.fieldHint,
    this.fieldInitial,
    this.fieldRequired = false,
    this.numeric = false,
    this.errorField,
  });

  final String confirmLabel;
  final String? backLabel;
  final bool danger;
  final String? fieldLabel, fieldHint, fieldInitial;
  final bool fieldRequired, numeric;

  /// The API's name for the field, to show its validation message under it.
  final String? errorField;
  final Future<String> Function(String value) run;

  @override
  State<ConfirmActions> createState() => _ConfirmActionsState();
}

class _ConfirmActionsState extends State<ConfirmActions> {
  late final _field = TextEditingController(text: widget.fieldInitial ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.run(_field.text.trim());
      if (mounted) Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = (widget.errorField == null ? null : e.field(widget.errorField!)) ?? e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'state.offline'.tr;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final hasField = widget.fieldLabel != null;
    final ready = !hasField || !widget.fieldRequired || _field.text.trim().length >= (widget.numeric ? 1 : 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasField) ...[
          VouchFlowTextField(
            label: widget.fieldLabel!,
            required: widget.fieldRequired,
            controller: _field,
            placeholder: widget.fieldHint,
            keyboardType: widget.numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
        ],
        if (_error != null) ...[
          Row(
            children: [
              Icon(PhosphorIconsRegular.warningCircle, size: 16, color: t.dangerStrong),
              const SizedBox(width: 6),
              Expanded(child: Text(_error!, style: VfType.small.copyWith(color: t.dangerStrong))),
            ],
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 14),
        VouchFlowActions(
          children: [
            VouchFlowButton(
              label: widget.backLabel ?? 'action.back'.tr,
              variant: VfButtonVariant.secondary,
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
            VouchFlowButton(
              label: widget.confirmLabel,
              variant: widget.danger ? VfButtonVariant.dangerSolid : VfButtonVariant.primary,
              loading: _busy,
              onPressed: ready ? _go : null,
            ),
          ],
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/erp_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/session_service.dart';
import '../../widgets/vf/vf.dart';
import '../erp/erp_widgets.dart';

/*
 * Pieces the Procurement, Finance and Assets screens share: money as the
 * books show it, the status badge every document carries, a page that loads
 * one thing, a list that pages and filters, a detail header, the action bar
 * and its confirmation sheet, and the label-and-amount row a statement is
 * made of on a phone.
 */

/// "TZS 1,250,000" in the company's base currency.
String finMoney(num? value, {String? currency, bool cents = false}) {
  final c = currency ?? ErpService.to.currency;
  final v = value ?? 0;
  return '$c ${cents ? ErpFmt.amount(v) : ErpFmt.amount(v.round())}';
}

/// "TZS 46.8M", for a figure that must fit a card.
String finCompact(num value) =>
    ErpFmt.compactMoney(value, ErpService.to.currency);

/// "Nov 2026" for a "2026-11" period.
String finPeriod(String period) {
  final parts = period.split('-');
  if (parts.length != 2) return period;
  final m = int.tryParse(parts[1]) ?? 1;
  return '${'fin.month.$m'.tr} ${parts[0]}';
}

/// A document's state as a badge, coloured the way the web's ProcStatus and
/// finance badges colour it: waiting is amber, done is green, refused red.
class FinStatusBadge extends StatelessWidget {
  const FinStatusBadge(this.status, {super.key, this.large = false});

  final String status;
  final bool large;

  static String tagOf(String status) => switch (status) {
    'submitted' ||
    'awaiting_approval' ||
    'partially_received' ||
    'partially_paid' ||
    'unpaid' ||
    'variance' => 'tag-warn',
    'approved' || 'sent' || 'open' => 'tag-info',
    'posted' ||
    'received' ||
    'closed' ||
    'paid' ||
    'active' ||
    'ordered' ||
    'matched' ||
    'awarded' => 'tag-accent',
    'rejected' || 'overdue' => 'tag-accent-2',
    _ => 'tag-neutral',
  };

  @override
  Widget build(BuildContext context) => VouchFlowStatusBadge(
    label: 'fin.status.$status'.tr,
    tag: tagOf(status),
    large: large,
  );
}

/// Loads one thing and builds a page from it, with pull to refresh, the
/// loader while it comes, and the API's own words when it does not.
class FinAsync<T> extends StatefulWidget {
  const FinAsync({
    super.key,
    required this.load,
    required this.builder,
    this.body = true,
  });

  final Future<T> Function() load;

  /// The page's children (inside an [ErpPageBody]) or, with [body] off, the
  /// whole page as one widget in the children's first slot.
  final List<Widget> Function(
    BuildContext context,
    T data,
    Future<void> Function() reload,
  )
  builder;
  final bool body;

  @override
  State<FinAsync<T>> createState() => FinAsyncState<T>();
}

class FinAsyncState<T> extends State<FinAsync<T>> {
  T? _data;
  String? _error;
  bool _loaded = false;

  T? get data => _data;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final data = await widget.load();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
          _loaded = true;
        });
      }
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

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const VfLoadingView();
    final data = _data;
    if (data == null) {
      return ErpPageBody(
        onRefresh: reload,
        children: [
          VouchFlowErrorState(
            message: _error ?? 'state.offline'.tr,
            onRetry: reload,
            retryLabel: 'action.retry'.tr,
          ),
        ],
      );
    }
    final children = widget.builder(context, data, reload);
    if (!widget.body) return children.first;
    return ErpPageBody(onRefresh: reload, children: children);
  }
}

/// One filter pill above a list: its label and the API's value (null for
/// everything).
class FinFilter {
  const FinFilter(this.label, this.value);

  final String label;
  final String? value;
}

/// A list that pages, searches and filters by status, the way the
/// Inventory documents list does, for any of the three apps' records.
class FinPagedList<T> extends StatefulWidget {
  const FinPagedList({
    super.key,
    required this.title,
    required this.load,
    required this.row,
    required this.emptyIcon,
    required this.emptyTitle,
    this.subtitle,
    this.filters = const [],
    this.initialFilter,
    this.searchPlaceholder,
    this.trailing,
    this.header,
    this.onOpen,
  });

  final String title;
  final String? subtitle;
  final Future<ErpPage<T>> Function(int page, String? filter, String q) load;

  /// One record as a list row; [divider] is off for the first.
  final Widget Function(
    BuildContext context,
    T item,
    bool divider,
    VoidCallback reload,
  )
  row;
  final IconData emptyIcon;
  final String emptyTitle;
  final List<FinFilter> filters;
  final String? initialFilter;
  final String? searchPlaceholder;
  final Widget? trailing;

  /// Shown above the rows, rebuilt with the first page (totals, a banner).
  final Widget Function(BuildContext context, ErpPage<T> first)? header;
  final VoidCallback? onOpen;

  @override
  State<FinPagedList<T>> createState() => FinPagedListState<T>();
}

class FinPagedListState<T> extends State<FinPagedList<T>> {
  late String? _filter = widget.initialFilter;
  String _q = '';
  Timer? _debounce;

  final _rows = <T>[];
  ErpPage<T>? _first;
  int _page = 1;
  bool _more = false, _loading = true, _loadingMore = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> reload({bool more = false}) async {
    final generation = more ? _generation : ++_generation;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = _rows.isEmpty;
        _error = null;
      }
    });
    try {
      final page = await widget.load(more ? _page + 1 : 1, _filter, _q.trim());
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) {
          _rows.clear();
          _first = page;
        }
        _rows.addAll(page.data);
        _page = page.currentPage;
        _more = page.hasMore;
      });
    } on ApiException catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'state.offline'.tr);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _search(String v) {
    _q = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), reload);
  }

  @override
  Widget build(BuildContext context) {
    return ErpPageBody(
      onRefresh: reload,
      children: [
        ErpPageTitle(
          widget.title,
          subtitle: widget.subtitle,
          trailing: widget.trailing,
        ),
        if (widget.searchPlaceholder != null) ...[
          VouchFlowSearchField(
            placeholder: widget.searchPlaceholder!,
            onChanged: _search,
          ),
          const SizedBox(height: 10),
        ],
        if (widget.filters.isNotEmpty) ...[
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in widget.filters) ...[
                  VouchFlowFilterChip(
                    label: f.label,
                    selected: _filter == f.value,
                    onTap: () {
                      setState(() => _filter = f.value);
                      reload();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_first != null && widget.header != null && !_loading)
          widget.header!(context, _first!),
        if (_loading)
          const VfLoadingView(inline: true)
        else if (_error != null && _rows.isEmpty)
          VouchFlowErrorState(
            message: _error!,
            onRetry: reload,
            retryLabel: 'action.retry'.tr,
          )
        else if (_rows.isEmpty)
          VouchFlowEmptyState(icon: widget.emptyIcon, title: widget.emptyTitle)
        else
          VouchFlowPanel(
            padded: false,
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++)
                  widget.row(context, _rows[i], i > 0, reload),
                if (_more)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _loadingMore
                        ? const VfLoader(size: 28)
                        : VouchFlowButton(
                            label: 'erp.loadMore'.tr,
                            variant: VfButtonVariant.ghost,
                            compact: true,
                            onPressed: () => reload(more: true),
                          ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// The head of a detail page: a tinted icon tile, what it is, its number,
/// a line of context and its badges.
class FinHead extends StatelessWidget {
  const FinHead({
    super.key,
    required this.icon,
    required this.kicker,
    required this.title,
    this.subtitle,
    this.badges = const [],
    this.tint,
    this.amount,
  });

  final IconData icon;
  final String kicker, title;
  final String? subtitle;
  final List<Widget> badges;
  final Color? tint;

  /// A headline figure under the title (an invoice's total).
  final String? amount;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final c = tint ?? t.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.withValues(alpha: t.isDark ? .18 : .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 25, color: c),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kicker,
                  style: VfType.small.copyWith(
                    color: t.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  title,
                  style: VfType.pageTitle.copyWith(
                    color: t.text,
                    fontSize: 19,
                    letterSpacing: -.3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: VfType.small.copyWith(color: t.text2)),
                ],
                if (amount != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    amount!,
                    style: VfType.figureS.copyWith(
                      color: t.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: badges),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The glass bar at the foot of a pushed page, holding its actions.
class FinActionBar extends StatelessWidget {
  const FinActionBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    // Only as tall as its buttons: the bar slot offers the whole screen.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VfGlass(
          borderRadius: BorderRadius.zero,
          fill: t.barFill,
          highlight: false,
          shadow: false,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                VfSize.pagePad,
                12,
                VfSize.pagePad,
                12,
              ),
              child: VouchFlowActions(children: children),
            ),
          ),
        ),
      ],
    );
  }
}

/// How a confirmation sheet asks for words: not at all, optionally, or as
/// a required reason (3 characters at least, as the API checks).
enum FinComment { none, optional, required }

/// Asks before a decision (approve, reject, post), with an optional or
/// required comment, runs [run] and closes with its message; the API's
/// refusal shows in place.
Future<String?> finConfirm(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required Future<String> Function(String comment) run,
  String? subtitle,
  IconData icon = PhosphorIconsRegular.checkCircle,
  VfTone tone = VfTone.info,
  List<VfSummaryRow> summary = const [],
  FinComment comment = FinComment.none,
  bool danger = false,
}) {
  return showVouchFlowDialog<String>(
    context,
    dialog: VouchFlowDialog(
      icon: icon,
      tone: tone,
      title: title,
      subtitle: subtitle,
      summary: summary,
      child: _ConfirmActions(
        confirmLabel: confirmLabel,
        run: run,
        comment: comment,
        danger: danger,
      ),
    ),
  );
}

class _ConfirmActions extends StatefulWidget {
  const _ConfirmActions({
    required this.confirmLabel,
    required this.run,
    required this.comment,
    required this.danger,
  });

  final String confirmLabel;
  final Future<String> Function(String comment) run;
  final FinComment comment;
  final bool danger;

  @override
  State<_ConfirmActions> createState() => _ConfirmActionsState();
}

class _ConfirmActionsState extends State<_ConfirmActions> {
  final _comment = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.run(_comment.text.trim());
      if (mounted) Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.field('comment') ?? e.field('reason') ?? e.message;
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
    final ready =
        widget.comment != FinComment.required ||
        _comment.text.trim().length >= 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.comment != FinComment.none) ...[
          VouchFlowTextField(
            label: widget.comment == FinComment.required
                ? 'fin.reason'.tr
                : 'fin.comment'.tr,
            required: widget.comment == FinComment.required,
            controller: _comment,
            placeholder: widget.comment == FinComment.required
                ? 'fin.reasonHint'.tr
                : 'fin.commentHint'.tr,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
        ],
        if (_error != null) ...[
          Row(
            children: [
              Icon(
                PhosphorIconsRegular.warningCircle,
                size: 16,
                color: t.dangerStrong,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: VfType.small.copyWith(color: t.dangerStrong),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 14),
        VouchFlowActions(
          children: [
            VouchFlowButton(
              label: 'action.back'.tr,
              variant: VfButtonVariant.secondary,
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
            VouchFlowButton(
              label: widget.confirmLabel,
              variant: widget.danger
                  ? VfButtonVariant.dangerSolid
                  : VfButtonVariant.primary,
              loading: _busy,
              onPressed: ready && !_busy ? _go : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// How much a statement line stands out: an account, a subtotal, a total.
enum FinRowWeight { line, subtotal, total }

/// A label on the left and an amount on the right: one line of a phone
/// statement. A second, quieter amount (last period, a budget) sits under
/// the first.
class FinAmountRow extends StatelessWidget {
  const FinAmountRow({
    super.key,
    required this.label,
    required this.amount,
    this.code,
    this.secondary,
    this.weight = FinRowWeight.line,
    this.divider = true,
    this.tone,
    this.onTap,
  });

  final String label;
  final String amount;
  final String? code;
  final String? secondary;
  final FinRowWeight weight;
  final bool divider;
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final strong = weight != FinRowWeight.line;
    final total = weight == FinRowWeight.total;
    final labelStyle = (strong ? VfType.bodyStrong : VfType.small).copyWith(
      color: t.text,
      fontSize: total ? 15.5 : (strong ? 14.5 : 14),
    );
    final amountStyle = (strong ? VfType.bodyStrong : VfType.small).copyWith(
      color: tone ?? t.text,
      fontSize: total ? 15.5 : (strong ? 14.5 : 14),
      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final row = Container(
      decoration: BoxDecoration(
        color: total ? t.primary.withValues(alpha: t.isDark ? .10 : .05) : null,
        border: divider
            ? Border(
                top: BorderSide(
                  color: t.border.withValues(alpha: .7),
                  width: .6,
                ),
              )
            : null,
      ),
      padding: EdgeInsets.fromLTRB(16, strong ? 12 : 10, 16, strong ? 12 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: labelStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (code != null && code!.isNotEmpty)
                  Text(
                    code!,
                    style: VfType.meta.copyWith(
                      color: t.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Long figures shrink to fit rather than push the label away.
          Flexible(
            flex: 2,
            child: Align(
              alignment: Alignment.topRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(amount, style: amountStyle),
                    if (secondary != null)
                      Text(
                        secondary!,
                        style: VfType.meta.copyWith(
                          color: t.muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// A section caption inside a statement ("Current assets").
class FinSectionLabel extends StatelessWidget {
  const FinSectionLabel(this.text, {super.key, this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, first ? 4 : 16, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: VfType.eyebrow.copyWith(color: t.muted, fontSize: 11.5),
      ),
    );
  }
}

/// Figure cards, one per row on a phone and two per row on a tablet.
class FinFigures extends StatelessWidget {
  const FinFigures({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 600) {
          return Column(
            children: [
              for (final c in children) ...[c, const SizedBox(height: 12)],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < children.length; i += 2) ...[
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
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

/// A thin progress track (received of ordered, depreciated of cost, spent
/// of budget).
class FinProgress extends StatelessWidget {
  const FinProgress({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
  });

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: t.border.withValues(alpha: t.isDark ? .5 : .8),
              ),
            ),
            FractionallySizedBox(
              heightFactor: 1,
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0, 1).toDouble(),
              child: ColoredBox(color: color ?? t.primary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short line in a panel when it has nothing to list.
class FinPanelEmpty extends StatelessWidget {
  const FinPanelEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(22),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: VfType.small.copyWith(color: context.vf.muted),
    ),
  );
}

/// A row's trailing amount with an optional badge under it.
class FinTrailing extends StatelessWidget {
  const FinTrailing({super.key, required this.amount, this.badge, this.tone});

  final String amount;
  final Widget? badge;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    // A row's title flexes; its trailing must not crowd it out on a phone.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 156),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VfType.small.copyWith(
              color: tone ?? t.text,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (badge != null) ...[const SizedBox(height: 4), badge!],
        ],
      ),
    );
  }
}

/// The opposite caret every tappable row ends with.
Widget finCaret(BuildContext context) =>
    Icon(PhosphorIconsBold.caretRight, size: 14, color: context.vf.faint);

/// A record pushed over the shell: loads it, titles the page from it,
/// builds its body and the actions its state and the person's permissions
/// allow (no bar when there are none).
class FinDetail<T> extends StatefulWidget {
  const FinDetail({
    super.key,
    required this.load,
    required this.title,
    required this.children,
    this.actions,
  });

  final Future<T> Function() load;
  final String Function(T? data) title;
  final List<Widget> Function(
    BuildContext context,
    T data,
    Future<void> Function() reload,
  )
  children;
  final List<Widget> Function(
    BuildContext context,
    T data,
    Future<void> Function() reload,
  )?
  actions;

  @override
  State<FinDetail<T>> createState() => _FinDetailState<T>();
}

class _FinDetailState<T> extends State<FinDetail<T>> {
  T? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.load();
      if (mounted) {
        setState(() {
          _data = d;
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
    final d = _data;
    final actions = d == null || widget.actions == null
        ? const <Widget>[]
        : widget.actions!(context, d, _load);
    return VouchFlowPushedScaffold(
      title: widget.title(d),
      body: d == null
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
          : ErpPageBody(
              onRefresh: _load,
              children: widget.children(context, d, _load),
            ),
      bottomBar: actions.isEmpty ? null : FinActionBar(children: actions),
    );
  }
}

/// The id a pushed page was opened with.
int finArgId() {
  final a = Get.arguments;
  if (a is int) return a;
  if (a is Map && a['id'] is int) return a['id'] as int;
  return int.tryParse('$a') ?? 0;
}

/// The signed-in person's id, for separation of duties (no one approves
/// what they raised).
int? finMe() => Get.isRegistered<SessionService>()
    ? Get.find<SessionService>().user.value?.id
    : null;

/// Opens a journal entry, for those who may read the ledger; null (no
/// link) for everyone else.
VoidCallback? finJournalTap(int id) => ErpService.to.can('accounting.view')
    ? () => Get.toNamed(
        '/erp/finance/journal',
        arguments: id,
        preventDuplicates: false,
      )
    : null;

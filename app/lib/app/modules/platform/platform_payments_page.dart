import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/models/platform_models.dart';
import '../../data/services/platform_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/vf/vf.dart';
import 'platform_widgets.dart';

/// Every invoice raised across all tenants (web: /platform/payments):
/// collected / outstanding totals, search, status and method filters, and
/// refund (paid) or mark paid (pending, failed) per invoice.
class PlatformPaymentsPage extends StatefulWidget {
  const PlatformPaymentsPage({super.key});

  @override
  State<PlatformPaymentsPage> createState() => _PlatformPaymentsPageState();
}

class _PlatformPaymentsPageState extends State<PlatformPaymentsPage> {
  final _repo = PlatformRepository.to;
  String _q = '', _status = '', _method = '';
  int _page = 1;
  PlatformPage<PlatformInvoice>? _result;
  String? _error;
  final Set<int> _busy = {};
  Timer? _debounce;
  int _seq = 0;

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
    final seq = ++_seq;
    setState(() => _error = null);
    try {
      final r = await _repo.payments(
        q: _q,
        status: _status,
        method: _method,
        page: _page,
      );
      if (mounted && seq == _seq) setState(() => _result = r);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = errorText(e));
    }
  }

  Future<void> _act(PlatformInvoice inv, bool refund) async {
    setState(() => _busy.add(inv.id));
    try {
      refund ? await _repo.refund(inv.id) : await _repo.markPaid(inv.id);
      showToast(
        refund ? 'platform.pay.refunded'.tr : 'platform.pay.markedPaid'.tr,
        body: inv.number,
        kind: refund ? ToastKind.warn : ToastKind.ok,
      );
      await _load();
    } catch (e) {
      showToast(
        'platform.pay.couldNotUpdate'.tr,
        body: errorText(e),
        kind: ToastKind.bad,
      );
    } finally {
      if (mounted) setState(() => _busy.remove(inv.id));
    }
  }

  void _filter(void Function() change) {
    setState(() {
      change();
      _page = 1;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final r = _result;
    final rows = r?.items ?? const <PlatformInvoice>[];
    return VouchFlowPageBody(
      onRefresh: _load,
      children: [
        VouchFlowPageHeader(
          kicker: 'platform.kicker'.tr,
          title: 'platform.pay.title'.tr,
          subtitle: 'platform.pay.sub'.tr,
        ),
        const SizedBox(height: 16),
        PlatformKpiGrid(
          children: [
            VouchFlowStatCard(
              label: 'platform.pay.collected'.tr,
              value: money(r?.metaNum('collected') ?? 0, 'TZS'),
              sub: 'platform.pay.collectedSub'.tr,
              icon: PhosphorIconsRegular.handCoins,
              tone: VfTone.ok,
            ),
            VouchFlowStatCard(
              label: 'platform.pay.outstanding'.tr,
              value: money(r?.metaNum('outstanding') ?? 0, 'TZS'),
              sub: 'platform.pay.outstandingSub'.tr,
              icon: PhosphorIconsRegular.hourglass,
              tone: VfTone.warn,
            ),
            VouchFlowStatCard(
              label: 'platform.pay.invoices'.tr,
              value: '${r?.total ?? 0}',
              sub: 'platform.pay.invoicesSub'.tr,
              icon: PhosphorIconsRegular.fileText,
            ),
          ],
        ),
        const SizedBox(height: 16),
        VouchFlowCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    VouchFlowSearchField(
                      placeholder: 'platform.search'.tr,
                      onChanged: (v) {
                        _q = v;
                        _page = 1;
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 260),
                          _load,
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    PlatformSelect<String>(
                      semanticLabel: 'platform.status'.tr,
                      value: _status,
                      items: [
                        ('', 'platform.allStatuses'.tr),
                        for (final s in const [
                          'paid',
                          'pending',
                          'failed',
                          'refunded',
                        ])
                          (s, statusLabel(s)),
                      ],
                      onChanged: (v) => _filter(() => _status = v),
                    ),
                    const SizedBox(height: 10),
                    PlatformSelect<String>(
                      semanticLabel: 'platform.pay.method'.tr,
                      value: _method,
                      items: [
                        ('', 'platform.allMethods'.tr),
                        ('mobile_money', 'platform.pay.mobileMoney'.tr),
                        ('card', 'platform.pay.card'.tr),
                        ('bank_transfer', 'platform.pay.bankTransfer'.tr),
                      ],
                      onChanged: (v) => _filter(() => _method = v),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: t.border),
              if (_error != null || r == null)
                platformPanelState(
                  loading: r == null,
                  error: _error,
                  onRetry: _load,
                )
              else if (rows.isEmpty)
                VouchFlowEmptyState(
                  icon: PhosphorIconsRegular.creditCard,
                  title: 'platform.noResults'.tr,
                )
              else ...[
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: t.border),
                  _invoiceRow(context, rows[i]),
                ],
                if (r.lastPage > 1) Divider(height: 1, color: t.border),
                PlatformPager(
                  page: r.page,
                  lastPage: r.lastPage,
                  total: r.total,
                  onChanged: (p) {
                    setState(() => _page = p);
                    _load();
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _invoiceRow(BuildContext context, PlatformInvoice inv) {
    final t = context.vf;
    final busy = _busy.contains(inv.id);
    final canRefund = inv.status == 'paid';
    final canMarkPaid = inv.status == 'pending' || inv.status == 'failed';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inv.number,
                      style: VfType.bodyStrong.copyWith(
                        color: t.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      inv.company ?? '—',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: VfType.small.copyWith(color: t.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    inv.amountText,
                    style: VfType.bodyStrong.copyWith(
                      color: t.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  VouchFlowStatusBadge(
                    label: statusLabel(inv.status),
                    tag: inv.statusTag,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          PlatformMetaLine(label: 'platform.plan'.tr, value: inv.description),
          PlatformMetaLine(
            label: 'platform.pay.method'.tr,
            value: inv.methodLabel,
          ),
          PlatformMetaLine(
            label: 'platform.pay.date'.tr,
            value: Fmt.date(inv.paidAt ?? inv.issuedAt),
          ),
          if (canRefund || canMarkPaid) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: canRefund
                  ? VouchFlowButton(
                      label: 'platform.pay.refund'.tr,
                      icon: PhosphorIconsRegular.arrowCounterClockwise,
                      variant: VfButtonVariant.danger,
                      compact: true,
                      loading: busy,
                      onPressed: busy ? null : () => _act(inv, true),
                    )
                  : VouchFlowButton(
                      label: 'platform.pay.markPaid'.tr,
                      icon: PhosphorIconsRegular.checkCircle,
                      variant: VfButtonVariant.secondary,
                      compact: true,
                      loading: busy,
                      onPressed: busy ? null : () => _act(inv, false),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

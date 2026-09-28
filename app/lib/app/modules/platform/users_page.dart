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

/// Every account across all tenants (web: /platform/users): search, role
/// and status filters, and suspend / activate per person.
class PlatformUsersPage extends StatefulWidget {
  const PlatformUsersPage({super.key});

  @override
  State<PlatformUsersPage> createState() => _PlatformUsersPageState();
}

class _PlatformUsersPageState extends State<PlatformUsersPage> {
  final _repo = PlatformRepository.to;
  String _q = '', _role = '', _status = '';
  int _page = 1;
  PlatformPage<PlatformUser>? _result;
  String? _error;
  Map<int, String> _companyNames = const {};
  final Set<int> _busy = {};
  Timer? _debounce;
  int _seq = 0;

  static const _roles = [
    'super_admin',
    'company_admin',
    'hod',
    'manager',
    'ceo',
    'cashier',
    'finance',
    'employee',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    // The listing carries company_id only; name it from the companies list.
    _repo
        .companyNames()
        .then((m) {
          if (mounted) setState(() => _companyNames = m);
        })
        .catchError((_) {});
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
      final r = await _repo.users(
        q: _q,
        role: _role,
        status: _status,
        page: _page,
      );
      if (mounted && seq == _seq) setState(() => _result = r);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = errorText(e));
    }
  }

  Future<void> _setStatus(PlatformUser u, String status) async {
    setState(() => _busy.add(u.id));
    try {
      await _repo.setUserStatus(u.id, status);
      final suspended = status == 'suspended';
      showToast(
        suspended
            ? 'platform.users.suspended'.tr
            : 'platform.users.activated'.tr,
        body: u.name,
        kind: suspended ? ToastKind.warn : ToastKind.ok,
      );
      await _load();
    } catch (e) {
      showToast(errorText(e), kind: ToastKind.bad);
    } finally {
      if (mounted) setState(() => _busy.remove(u.id));
    }
  }

  String _roleFilterLabel(String r) {
    final key = 'platform.roleFilter.$r';
    return key.tr == key ? roleLabel(r) : key.tr;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final rows = _result?.items ?? const <PlatformUser>[];
    return VouchFlowPageBody(
      onRefresh: _load,
      children: [
        VouchFlowPageHeader(
          kicker: 'platform.kicker'.tr,
          title: 'platform.users'.tr,
          subtitle: 'platform.users.sub'.tr,
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
                      semanticLabel: 'platform.users.role'.tr,
                      value: _role,
                      items: [
                        ('', 'platform.allRoles'.tr),
                        for (final r in _roles) (r, _roleFilterLabel(r)),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _role = v;
                          _page = 1;
                        });
                        _load();
                      },
                    ),
                    const SizedBox(height: 10),
                    PlatformSelect<String>(
                      semanticLabel: 'platform.status'.tr,
                      value: _status,
                      items: [
                        ('', 'platform.allStatuses'.tr),
                        for (final s in const [
                          'active',
                          'invited',
                          'suspended',
                        ])
                          (s, statusLabel(s)),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _status = v;
                          _page = 1;
                        });
                        _load();
                      },
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: t.border),
              if (_error != null || _result == null)
                platformPanelState(
                  loading: _result == null,
                  error: _error,
                  onRetry: _load,
                )
              else if (rows.isEmpty)
                VouchFlowEmptyState(
                  icon: PhosphorIconsRegular.usersThree,
                  title: 'platform.noResults'.tr,
                )
              else ...[
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: t.border),
                  _userRow(context, rows[i]),
                ],
                if (_result!.lastPage > 1) Divider(height: 1, color: t.border),
                PlatformPager(
                  page: _result!.page,
                  lastPage: _result!.lastPage,
                  total: _result!.total,
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

  Widget _userRow(BuildContext context, PlatformUser u) {
    final t = context.vf;
    final tag = u.status == 'active'
        ? 'tag-accent'
        : (u.status == 'invited' ? 'tag-outline' : 'tag-accent-2');
    final busy = _busy.contains(u.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlatformPerson(
                  name: u.name,
                  sub: u.email,
                  initials: u.displayInitials,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (u.companyId == null)
                      VouchFlowStatusBadge(
                        label: 'platform.platformBadge'.tr,
                        tag: 'tag-info',
                      )
                    else
                      Text(
                        _companyNames[u.companyId] ?? '—',
                        style: VfType.small.copyWith(
                          color: t.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    Text(
                      '· ${u.roleLabel}',
                      style: VfType.small.copyWith(color: t.text2),
                    ),
                    VouchFlowStatusBadge(
                      label: statusLabel(u.status),
                      tag: tag,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${'platform.users.lastSeen'.tr}: ${Fmt.dateTime(u.lastLoginAt)}',
                  style: VfType.meta.copyWith(color: t.muted),
                ),
              ],
            ),
          ),
          busy
              ? const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : u.status != 'suspended'
              ? VouchFlowIconButton(
                  icon: PhosphorIconsRegular.prohibit,
                  tooltip: 'platform.suspend'.tr,
                  color: t.dangerStrong,
                  onPressed: () => _setStatus(u, 'suspended'),
                )
              : VouchFlowIconButton(
                  icon: PhosphorIconsRegular.checkCircle,
                  tooltip: 'platform.activate'.tr,
                  onPressed: () => _setStatus(u, 'active'),
                ),
        ],
      ),
    );
  }
}

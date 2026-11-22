import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../widgets/vf/vf.dart';
import '../dashboard/dash_bits.dart' show dashDate, dashIsSw;
import '../shell/areas.dart';
import '../shell/shell_page.dart';

/// The launcher: every app this person can open, as an icon with its name,
/// in the order a business thinks about its work, with a count on any app
/// where something is waiting. Apps the plan allows but the company has
/// not switched on follow, greyed, for the people who can switch them on
/// (the web's /home).
class LauncherPage extends StatefulWidget {
  const LauncherPage({super.key});

  @override
  State<LauncherPage> createState() => _LauncherPageState();
}

class _LauncherPageState extends State<LauncherPage> {
  final c = Get.find<ShellController>();
  String _q = '';

  static const _weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _weekdaysSw = ['Jumatatu', 'Jumanne', 'Jumatano', 'Alhamisi', 'Ijumaa', 'Jumamosi', 'Jumapili'];

  String _today() {
    final now = DateTime.now();
    return '${(dashIsSw ? _weekdaysSw : _weekdaysEn)[now.weekday - 1]} · ${dashDate(now)}';
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return (h < 12 ? 'apps.greeting.morning' : h < 17 ? 'apps.greeting.afternoon' : 'apps.greeting.evening').tr;
  }

  bool _matches(VfArea a) {
    final q = _q.trim().toLowerCase();
    return q.isEmpty || a.label.tr.toLowerCase().contains(q) || a.blurb.tr.toLowerCase().contains(q);
  }

  void _explainOff(VfArea a) {
    final name = a.label.tr;
    showVouchFlowDialog<void>(
      context,
      dialog: VouchFlowDialog(
        title: 'apps.offTitle'.trParams({'app': name}),
        subtitle: 'apps.offBody'.trParams({'app': name}),
        actions: [
          Builder(
            builder: (ctx) => VouchFlowButton(label: 'apps.gotIt'.tr, onPressed: () => Navigator.of(ctx).pop()),
          ),
        ],
        child: Align(alignment: Alignment.centerLeft, child: VfAppIcon(app: a.key, size: 56, dimmed: true)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Obx(() {
      final apps = c.apps;
      final counts = c.appCounts;
      final pending = c.pendingCount.value;
      final first = c.session.user.value?.name.split(' ').first ?? '';
      final open = [
        for (final cat in vfAreaCategories)
          ...apps.open.where((a) => a.category == cat && _matches(a)),
      ];
      final off = apps.off.where(_matches).toList();

      int? badge(String key) => key == 'vouchflow' ? pending : counts[key];

      return LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final columns = w >= 1000 ? 6 : w >= 800 ? 5 : w >= 600 ? 4 : 3;
          final icon = w >= 600 ? 84.0 : 72.0;
          final side = w > 1100 ? (w - 1040) / 2 : (w >= 600 ? 32.0 : VfSize.pagePad);

          Widget grid(List<VfArea> areas, {bool dimmed = false}) => GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 18,
            crossAxisSpacing: 6,
            childAspectRatio: (w - side * 2) / columns / (icon + 58),
            children: [
              for (final a in areas)
                _AppTile(
                  area: a,
                  size: icon,
                  badge: dimmed ? null : badge(a.key),
                  dimmed: dimmed,
                  onTap: () => dimmed ? _explainOff(a) : c.openApp(a.key),
                ),
            ],
          );

          return ListView(
            padding: EdgeInsets.fromLTRB(side, 18, side, 36),
            children: [
              Text(
                _today().toUpperCase(),
                style: VfType.eyebrow.copyWith(fontSize: 12.5, color: t.muted, letterSpacing: .4),
              ),
              const SizedBox(height: 6),
              Semantics(
                header: true,
                child: Text(
                  first.isEmpty ? _greeting() : '${_greeting()}, $first',
                  style: VfType.display.copyWith(color: t.text, fontSize: w >= 600 ? 28 : 24, letterSpacing: -.4),
                ),
              ),
              const SizedBox(height: 18),
              VouchFlowSearchField(placeholder: 'apps.search'.tr, onChanged: (v) => setState(() => _q = v)),
              const SizedBox(height: 28),
              if (open.isNotEmpty) grid(open),
              if (off.isNotEmpty) ...[
                const SizedBox(height: 34),
                Text(
                  'apps.more'.tr,
                  style: VfType.bodyStrong.copyWith(color: t.text2, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text('apps.offAdmin'.tr, style: VfType.meta.copyWith(color: t.faint)),
                const SizedBox(height: 18),
                grid(off, dimmed: true),
              ],
              if (open.isEmpty && off.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text('apps.none'.tr, textAlign: TextAlign.center, style: VfType.body.copyWith(color: t.muted)),
                ),
            ],
          );
        },
      );
    });
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.area, required this.size, required this.onTap, this.badge, this.dimmed = false});

  final VfArea area;
  final double size;
  final int? badge;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final name = area.label.tr;
    return Semantics(
      button: true,
      label: [
        name,
        if (badge != null && badge! > 0) 'apps.waiting'.trParams({'n': '$badge'}),
        if (dimmed) 'apps.offAdmin'.tr,
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            VfAppIcon(app: area.key, size: size, badge: badge, dimmed: dimmed),
            const SizedBox(height: 10),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: VfType.label.copyWith(
                fontSize: 13.5,
                height: 1.25,
                color: dimmed ? t.muted : t.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app switcher: the apps as a compact grid in a sheet, from the top
/// bar's app name, and a way back to the launcher.
Future<void> showAppSwitcher(BuildContext context, ShellController c) {
  return showVfSheet<void>(
    context,
    builder: (ctx) {
      final t = ctx.vf;
      final apps = c.apps;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('apps.switch'.tr, style: VfType.sectionTitle.copyWith(color: t.text))),
                  VouchFlowButton(
                    label: 'apps.allApps'.tr,
                    icon: PhosphorIconsRegular.squaresFour,
                    variant: VfButtonVariant.secondary,
                    compact: true,
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      c.go('/home');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, box) {
                  final columns = box.maxWidth >= 520 ? 6 : 4;
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    childAspectRatio: .78,
                    children: [
                      for (final a in apps.open)
                        Obx(() {
                          final current = c.area.value == a.key;
                          return InkWell(
                            borderRadius: BorderRadius.circular(VfSize.radiusL),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              c.openApp(a.key);
                            },
                            child: Column(
                              children: [
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: current ? t.primary : Colors.transparent, width: 2),
                                  ),
                                  child: VfAppIcon(
                                    app: a.key,
                                    size: 52,
                                    shadow: false,
                                    badge: a.key == 'vouchflow' ? c.pendingCount.value : c.appCounts[a.key],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  a.label.tr,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: VfType.meta.copyWith(
                                    fontSize: 12,
                                    color: current ? t.primaryText : t.text,
                                    fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

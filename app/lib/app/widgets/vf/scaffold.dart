import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import 'glass.dart';

/// A round glass icon button for app bars (back, close, more).
class VfBarButton extends StatelessWidget {
  const VfBarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// A small red dot in the corner (unread notifications).
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: t.glassFillStrong,
            shape: CircleBorder(
              side: BorderSide(color: t.isDark ? t.glassBorder : t.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(icon, size: 19, color: t.text, semanticLabel: tooltip),
              ),
            ),
          ),
          if (badge)
            Positioned(
              top: 9,
              right: 10,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: t.dangerStrong,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.background, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A page pushed over the shell (voucher detail, create voucher, a company):
/// the glass wallpaper, a clear app bar with a round glass back button and a
/// centred title.
class VouchFlowPushedScaffold extends StatelessWidget {
  const VouchFlowPushedScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottomBar,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottomBar;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return VfWallpaper(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        systemOverlayStyle: VfTheme.overlay(t.isDark),
        toolbarHeight: VfSize.topBarH,
        leadingWidth: 64,
        leading: Center(
          child: VfBarButton(
            icon: PhosphorIconsRegular.caretLeft,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: VfType.cardTitle.copyWith(color: t.text, fontSize: 17),
        ),
        actionsPadding: const EdgeInsets.only(right: 10),
        actions: actions,
      ),
      body: body,
      // A bar sized to its content, never the whole page, whatever it is built from.
      bottomNavigationBar: bottomBar == null
          ? null
          : Column(mainAxisSize: MainAxisSize.min, children: [bottomBar!]),
      floatingActionButton: floatingActionButton,
      ),
    );
  }
}

/// A shell page's scrollable body: the phone gutter, pull to refresh, and
/// room at the bottom above the floating tab bar.
class VouchFlowPageBody extends StatelessWidget {
  const VouchFlowPageBody({super.key, required this.children, this.onRefresh, this.padding});

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    // Clear of the system navigation bar on a page drawn edge to edge (zero
    // inside the shell, whose tab bar already sits above it).
    final inset = MediaQuery.paddingOf(context).bottom;
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: (padding ?? const EdgeInsets.fromLTRB(VfSize.pagePad, 8, VfSize.pagePad, 32))
          .add(EdgeInsets.only(bottom: inset)),
      children: children,
    );
    if (onRefresh == null) return list;
    final t = context.vf;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      color: t.primary,
      backgroundColor: t.isDark ? t.surface2 : t.surface,
      child: list,
    );
  }
}

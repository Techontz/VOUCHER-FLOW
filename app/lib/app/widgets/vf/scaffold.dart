import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';

/// A round, softly filled icon button for app bars (back, close, more).
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
            color: t.isDark ? t.surface : t.surface,
            shape: CircleBorder(
              side: BorderSide(color: t.isDark ? t.border : t.border.withValues(alpha: .7)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(icon, size: 20, color: t.text, semanticLabel: tooltip),
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
                  border: Border.all(color: t.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A page pushed over the shell (voucher detail, create voucher, a company):
/// an app bar in the page's own colour with a round back button and a
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
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        systemOverlayStyle: t.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
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
      bottomNavigationBar: bottomBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// A shell page's scrollable body: the phone gutter, pull to refresh, and
/// room at the bottom for the floating tab bar.
class VouchFlowPageBody extends StatelessWidget {
  const VouchFlowPageBody({super.key, required this.children, this.onRefresh, this.padding});

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding ?? const EdgeInsets.fromLTRB(VfSize.pagePad, 8, VfSize.pagePad, 32),
      children: children,
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

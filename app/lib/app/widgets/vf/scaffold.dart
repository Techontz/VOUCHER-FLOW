import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';

/// A page pushed over the shell (voucher detail, create voucher, a company):
/// the same navy chrome as the top bar, with a back button and a title.
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
        backgroundColor: t.chrome,
        toolbarHeight: VfSize.topBarH,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(PhosphorIconsRegular.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: VfType.cardTitle.copyWith(color: Colors.white)),
        actions: actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: t.chromeLine),
        ),
      ),
      body: body,
      bottomNavigationBar: bottomBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// A shell page's scrollable body: the web's 16px phone gutter, pull to
/// refresh, and room at the bottom for the tab bar.
class VouchFlowPageBody extends StatelessWidget {
  const VouchFlowPageBody({super.key, required this.children, this.onRefresh, this.padding});

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding ?? const EdgeInsets.fromLTRB(VfSize.pagePad, 20, VfSize.pagePad, 32),
      children: children,
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

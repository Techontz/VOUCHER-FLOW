import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/services/erp_service.dart';
import '../../data/services/session_service.dart';
import '../../widgets/vf/vf.dart';
import '../shell/app_registry.dart';
import '../shell/shell_page.dart';

/*
 * Pieces every ERP app's screens share. The gate is the important one: it
 * settles loading, a company that has not set up, a module that is off and
 * a role without the permission, once, the same way on every screen, so a
 * page body only ever builds for someone the API will actually answer.
 */

/// Builds [builder] only when the company runs [module] and the person
/// holds [permission] (the web's `ErpGate`).
class ErpGate extends StatelessWidget {
  const ErpGate({super.key, this.module, this.permission, required this.builder});

  final String? module;
  final String? permission;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final erp = ErpService.to;
    return Obx(() {
      if (!erp.settled.value) return const VfLoadingView();
      final config = erp.config.value;
      if (config == null || !config.isSetUp) {
        final admin = Get.isRegistered<SessionService>() && Get.find<SessionService>().user.value?.role == 'company_admin';
        return ErpEmpty(
          icon: PhosphorIconsRegular.rocketLaunch,
          title: 'erp.notSetUpTitle'.tr,
          body: admin ? 'erp.notSetUpBody'.tr : 'erp.notSetUpOthers'.tr,
        );
      }
      if (module != null && !config.has(module!)) {
        return ErpEmpty(icon: PhosphorIconsRegular.toggleLeft, title: 'erp.moduleOff'.tr);
      }
      if (permission != null && !config.can(permission!)) {
        return ErpEmpty(icon: PhosphorIconsRegular.lockSimple, title: 'erp.noAccess'.tr);
      }
      return builder(context);
    });
  }
}

/// A whole-page empty, locked or switched-off state, centred.
class ErpEmpty extends StatelessWidget {
  const ErpEmpty({super.key, required this.icon, required this.title, this.body, this.action});

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(VfSize.pagePad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VouchFlowEmptyState(icon: icon, title: title, body: body),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// A shell page's scrolling body for ERP screens: the phone gutter, a
/// readable width on tablets, pull to refresh, and room above the tab bar.
class ErpPageBody extends StatelessWidget {
  const ErpPageBody({super.key, required this.children, this.onRefresh, this.controller});

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;

  /// Cards stop growing here; a tablet shows the page centred.
  static const maxWidth = 760.0;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final list = LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth > maxWidth + 48 ? (box.maxWidth - maxWidth) / 2 : VfSize.pagePad;
        return ListView(
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(side, 12, side, 32),
          children: children,
        );
      },
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      color: t.primary,
      backgroundColor: t.isDark ? t.surface2 : t.surface,
      child: list,
    );
  }
}

/// A page title for an ERP screen: bold, tight, with an optional quieter
/// line under it.
class ErpPageTitle extends StatelessWidget {
  const ErpPageTitle(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: VfType.pageTitle.copyWith(color: t.text, fontSize: 23, letterSpacing: -.6),
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: VfType.small.copyWith(color: t.muted)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Opens one of the shell's destinations ('/erp/documents' …), from a card
/// or a "View all" inside an app.
void erpGo(String href) {
  if (Get.isRegistered<ShellController>()) Get.find<ShellController>().go(href);
}

/// Runs one of an app's create actions: its own tab, or a page pushed over
/// the shell.
Future<void> erpCreate(VfCreateAction action) async {
  if (Get.isRegistered<ShellController>()) {
    return Get.find<ShellController>().runCreate(action);
  }
  await Get.toNamed(action.route, arguments: action.arguments);
}

/// Space between the cards of an ERP page.
const erpGap = SizedBox(height: 14);

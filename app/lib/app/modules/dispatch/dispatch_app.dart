import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../routes/routes.dart';
import '../shell/app_registry.dart';
import '../shell/nav.dart';
import 'loading_list_page.dart';
import 'verification_page.dart';

/*
 * The Dispatch app (the web's dispatch entries in lib/modules/sales.ts):
 * the loading register, the trucks on the road waiting for proof of
 * delivery, and finance verification. Delivery notes and gate passes are
 * stages of a loading order here, not separate lists; printing stays on
 * the web.
 */

const _dispatch = 'dispatch';

const dispatchNav = [
  VfNavItem(
    '/erp/dispatch',
    'dsp.nav.loading',
    PhosphorIconsRegular.package,
    PhosphorIconsFill.package,
    module: _dispatch,
    permissions: ['dispatch.view'],
  ),
  VfNavItem(
    '/erp/dispatch/deliveries',
    'dsp.nav.deliveries',
    PhosphorIconsRegular.truck,
    PhosphorIconsFill.truck,
    module: _dispatch,
    permissions: ['dispatch.view'],
  ),
  VfNavItem(
    '/erp/dispatch/verification',
    'dsp.nav.verification',
    PhosphorIconsRegular.shieldCheck,
    PhosphorIconsFill.shieldCheck,
    module: _dispatch,
    permissions: ['dispatch.verify'],
  ),
];

const dispatchCreateActions = [
  VfCreateAction(
    label: 'dsp.newLoading',
    hint: 'dsp.hint.loading',
    icon: PhosphorIconsRegular.truck,
    route: Routes.dispatchLoadingNew,
    permission: 'dispatch.load',
  ),
];

final dispatchApp = VfAppModule(
  area: _dispatch,
  nav: dispatchNav,
  pages: {
    '/erp/dispatch': (_) => const LoadingOrdersPage(),
    '/erp/dispatch/deliveries': (_) => const DeliveriesPage(),
    '/erp/dispatch/verification': (_) => const VerificationPage(),
  },
  create: dispatchCreateActions,
);

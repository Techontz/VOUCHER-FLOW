import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../routes/routes.dart';
import '../shell/app_registry.dart';
import '../shell/nav.dart';
import 'activities_page.dart';
import 'leads_page.dart';
import 'overview_page.dart';
import 'pipeline_page.dart';

/*
 * The CRM app, as the shell sees it (the web's lib/modules/crm.ts): the
 * day's follow-ups and the pipeline's figures, the pipeline by stage, the
 * leads and the activities, all behind crm.view; the API narrows each to
 * the person's own records unless they hold crm.view_all. The "+" adds a
 * lead or logs a call, meeting, visit or task (crm.manage).
 */

const _crm = 'crm';

const crmNav = [
  VfNavItem('/erp/crm', 'crm.nav.overview', PhosphorIconsRegular.house, PhosphorIconsFill.house,
      module: _crm, permissions: ['crm.view']),
  VfNavItem('/erp/crm/pipeline', 'crm.nav.pipeline', PhosphorIconsRegular.kanban, PhosphorIconsFill.kanban,
      module: _crm, permissions: ['crm.view']),
  VfNavItem('/erp/crm/leads', 'crm.nav.leads', PhosphorIconsRegular.userFocus, PhosphorIconsFill.userFocus,
      module: _crm, permissions: ['crm.view']),
  VfNavItem('/erp/crm/activities', 'crm.nav.activities', PhosphorIconsRegular.calendarCheck, PhosphorIconsFill.calendarCheck,
      module: _crm, permissions: ['crm.view']),
];

const crmCreateActions = [
  VfCreateAction(
    label: 'crm.logActivity',
    hint: 'crm.logActivityHint',
    icon: PhosphorIconsRegular.phoneCall,
    route: Routes.crmActivityNew,
    permission: 'crm.manage',
  ),
  VfCreateAction(
    label: 'crm.newLead',
    hint: 'crm.newLeadHint',
    icon: PhosphorIconsRegular.userPlus,
    route: Routes.crmLeadNew,
    permission: 'crm.manage',
  ),
];

final crmApp = VfAppModule(
  area: _crm,
  nav: crmNav,
  pages: {
    '/erp/crm': (_) => const CrmOverviewPage(),
    '/erp/crm/pipeline': (_) => const CrmPipelinePage(),
    '/erp/crm/leads': (_) => const CrmLeadsPage(),
    '/erp/crm/activities': (_) => const CrmActivitiesPage(),
  },
  create: crmCreateActions,
);

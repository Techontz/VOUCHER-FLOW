import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../routes/routes.dart';
import '../shell/app_registry.dart';
import '../shell/nav.dart';
import 'expiring_page.dart';
import 'library_page.dart';

/*
 * The Documents app, as the shell sees it (the web's /erp/files): the
 * library, folder by folder with search, and what expires soon, behind
 * documents.view; the "+" uploads from the phone (documents.upload).
 */

const _documents = 'documents';

const filesNav = [
  VfNavItem('/erp/files', 'dms.nav.library', PhosphorIconsRegular.folders, PhosphorIconsFill.folders,
      module: _documents, permissions: ['documents.view']),
  VfNavItem('/erp/files/expiring', 'dms.nav.expiring', PhosphorIconsRegular.calendarX, PhosphorIconsFill.calendarX,
      module: _documents, permissions: ['documents.view']),
];

const filesCreateActions = [
  VfCreateAction(
    label: 'dms.upload',
    hint: 'dms.uploadHint',
    icon: PhosphorIconsRegular.uploadSimple,
    route: Routes.filesUpload,
    permission: 'documents.upload',
  ),
];

final filesApp = VfAppModule(
  area: 'files',
  nav: filesNav,
  pages: {
    '/erp/files': (_) => const FilesLibraryPage(),
    '/erp/files/expiring': (_) => const FilesExpiringPage(),
  },
  create: filesCreateActions,
);

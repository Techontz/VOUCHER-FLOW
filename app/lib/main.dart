import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'app/modules/approvals/bulk_approve_page.dart';
import 'app/core/theme.dart';
import 'app/core/translations.dart';
import 'app/data/services/api_service.dart';
import 'app/data/services/erp_service.dart';
import 'app/data/services/session_service.dart';
import 'app/data/services/voucher_repository.dart';
import 'app/modules/auth/forgot_password_page.dart';
import 'app/modules/auth/login_page.dart';
import 'app/modules/auth/register_page.dart';
import 'app/modules/platform/company_detail_page.dart';
import 'app/modules/auth/splash_page.dart';
import 'app/modules/auth/verify_login_page.dart';
import 'app/modules/branding/branding_page.dart';
import 'app/modules/dashboard/dashboard_tab.dart';
import 'app/modules/inventory/document_form_page.dart';
import 'app/modules/inventory/document_page.dart';
import 'app/modules/inventory/product_page.dart';
import 'app/modules/sales/customer_page.dart';
import 'app/modules/sales/invoice_page.dart';
import 'app/modules/sales/order_form_page.dart';
import 'app/modules/sales/order_page.dart';
import 'app/modules/sales/quotation_page.dart';
import 'app/modules/sales/receipt_form_page.dart';
import 'app/modules/sales/receipt_page.dart';
import 'app/modules/dispatch/loading_form_page.dart';
import 'app/modules/dispatch/loading_page.dart';
import 'app/modules/notifications/notifications_tab.dart';
import 'app/modules/procurement/invoice_page.dart';
import 'app/modules/procurement/order_page.dart';
import 'app/modules/procurement/payment_page.dart';
import 'app/modules/procurement/requisition_form_page.dart';
import 'app/modules/procurement/requisition_page.dart';
import 'app/modules/procurement/supplier_page.dart';
import 'app/modules/finance/cashbook_page.dart';
import 'app/modules/finance/detail_pages.dart';
import 'app/modules/assets/assets_pages.dart';
import 'app/modules/production/boms_page.dart';
import 'app/modules/production/order_form_page.dart';
import 'app/modules/production/order_page.dart';
import 'app/modules/crm/crm_forms.dart';
import 'app/modules/crm/lead_page.dart';
import 'app/modules/crm/opportunity_page.dart';
import 'app/modules/files/file_page.dart';
import 'app/modules/files/upload_page.dart';
import 'app/modules/profile/profile_tab.dart';
import 'app/modules/fleet/fuel_form_page.dart';
import 'app/modules/fleet/trip_page.dart';
import 'app/modules/fleet/vehicle_page.dart';
import 'app/modules/hr/employee_page.dart';
import 'app/modules/hr/leave_form_page.dart';
import 'app/modules/hr/payroll_run_page.dart';
import 'app/modules/hr/payslip_page.dart';
import 'app/modules/shell/shell_page.dart';
import 'app/modules/vouchers/create_voucher_page.dart';
import 'app/modules/vouchers/voucher_detail_page.dart';
import 'app/routes/routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind see-through status and navigation bars on every Android
  // version, as Android 15 and newer insist on; pages pad for the insets.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // The Inter typeface's licence (SIL OFL 1.1), on the app's licences page.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Inter'],
      await rootBundle.loadString('assets/fonts/OFL.txt'),
    );
  });

  // Services are permanent: one API client, one session, resolved everywhere.
  final api = await Get.putAsync(() => ApiService().init(), permanent: true);
  Get.put(VoucherRepository(api), permanent: true);
  final session = await Get.putAsync(
    () => SessionService(api).init(),
    permanent: true,
  );
  // The ERP configuration follows the session: read on sign-in, forgotten
  // on sign-out.
  Get.put(ErpService(api, session), permanent: true);

  runApp(VouchFlowApp(session: session));
}

class VouchFlowApp extends StatelessWidget {
  const VouchFlowApp({super.key, required this.session});

  final SessionService session;

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the company's colour changes: the themes are built from
    // VfColors.palette, which SessionService sets before this reads it.
    return Obx(() {
      session.accent.value;
      return _app();
    });
  }

  Widget _app() {
    return GetMaterialApp(
      title: 'VouchFlow',
      debugShowCheckedModeBanner: false,
      theme: VfTheme.light(),
      darkTheme: VfTheme.dark(),
      themeMode: session.themeMode.value,
      translations: VfTranslations(),
      locale: Locale(session.locale.value),
      fallbackLocale: const Locale('en'),
      // Screens without an app bar (splash, sign-in) still get bars whose
      // icons read on the appearance.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: VfTheme.overlay(Theme.of(context).brightness == Brightness.dark),
        child: child ?? const SizedBox.shrink(),
      ),
      initialRoute: Routes.splash,
      defaultTransition: Transition.cupertino,
      getPages: [
        GetPage(name: Routes.splash, page: () => const SplashPage()),
        GetPage(
          name: Routes.login,
          page: () => const LoginPage(),
          binding: BindingsBuilder(() => Get.lazyPut(LoginController.new)),
        ),
        GetPage(
          name: Routes.verifyLogin,
          page: () => const VerifyLoginPage(),
          binding: BindingsBuilder(
            () => Get.lazyPut(VerifyLoginController.new),
          ),
        ),
        GetPage(
          name: Routes.shell,
          page: () => const ShellPage(),
          binding: BindingsBuilder(() {
            Get.put(ShellController());
            Get.lazyPut(DashboardController.new);
            Get.lazyPut(NotificationsController.new);
            Get.lazyPut(ProfileController.new);
            Get.lazyPut(BrandingController.new, fenix: true);
          }),
        ),
        GetPage(name: Routes.voucher, page: () => const VoucherDetailPage()),
        GetPage(name: Routes.bulkApprove, page: () => const BulkApprovePage()),
        GetPage(name: Routes.register, page: () => const RegisterPage()),
        GetPage(name: Routes.forgotPassword, page: () => const ForgotPasswordPage()),
        GetPage(name: Routes.platformCompany, page: () => const PlatformCompanyPage()),
        GetPage(name: Routes.erpDocument, page: () => const DocumentPage()),
        GetPage(name: Routes.erpDocumentNew, page: () => const DocumentFormPage()),
        GetPage(name: Routes.erpProduct, page: () => const ProductPage()),
        GetPage(name: Routes.prcRequisition, page: () => const RequisitionPage()),
        GetPage(name: Routes.prcRequisitionNew, page: () => const RequisitionFormPage()),
        GetPage(name: Routes.prcOrder, page: () => const PurchaseOrderPage()),
        GetPage(name: Routes.prcInvoice, page: () => const SupplierInvoicePage()),
        GetPage(name: Routes.prcPayment, page: () => const SupplierPaymentPage()),
        GetPage(name: Routes.prcSupplier, page: () => const SupplierPage()),
        GetPage(name: Routes.finBank, page: () => const BankAccountPage()),
        GetPage(name: Routes.finJournal, page: () => const JournalPage()),
        GetPage(name: Routes.finCashbookEntry, page: () => const CashbookEntryPage()),
        GetPage(name: Routes.finCashbookNew, page: () => const CashbookFormPage()),
        GetPage(name: Routes.astAsset, page: () => const AssetPage()),
        GetPage(name: Routes.astRun, page: () => const DepreciationRunPage()),
        GetPage(name: Routes.erpFleetTrip, page: () => const TripPage()),
        GetPage(name: Routes.erpFleetVehicle, page: () => const VehiclePage()),
        GetPage(name: Routes.erpFleetFuelNew, page: () => const FuelFormPage()),
        GetPage(name: Routes.erpHrEmployee, page: () => const EmployeePage()),
        GetPage(name: Routes.erpHrPayslip, page: () => const PayslipPage()),
        GetPage(name: Routes.erpHrPayrollRun, page: () => const PayrollRunPage()),
        GetPage(name: Routes.erpHrLeaveNew, page: () => const LeaveFormPage()),
        GetPage(name: Routes.salesOrder, page: () => const SalesOrderPage()),
        GetPage(name: Routes.salesQuotation, page: () => const SalesQuotationPage()),
        GetPage(name: Routes.salesInvoice, page: () => const SalesInvoicePage()),
        GetPage(name: Routes.salesReceipt, page: () => const SalesReceiptPage()),
        GetPage(name: Routes.salesCustomer, page: () => const SalesCustomerPage()),
        GetPage(name: Routes.salesDocumentNew, page: () => const SalesDocumentFormPage()),
        GetPage(name: Routes.salesReceiptNew, page: () => const SalesReceiptFormPage()),
        GetPage(name: Routes.dispatchLoading, page: () => const LoadingOrderPage()),
        GetPage(name: Routes.dispatchLoadingNew, page: () => const LoadingFormPage()),
        GetPage(name: Routes.prdOrder, page: () => const ProductionOrderPage()),
        GetPage(name: Routes.prdOrderNew, page: () => const ProductionOrderFormPage()),
        GetPage(name: Routes.prdBom, page: () => const BomPage()),
        GetPage(name: Routes.crmLead, page: () => const CrmLeadPage()),
        GetPage(name: Routes.crmLeadNew, page: () => const CrmLeadFormPage()),
        GetPage(name: Routes.crmOpportunity, page: () => const CrmOpportunityPage()),
        GetPage(name: Routes.crmActivityNew, page: () => const CrmActivityFormPage()),
        GetPage(name: Routes.filesDocument, page: () => const FilesDocumentPage()),
        GetPage(name: Routes.filesUpload, page: () => const FilesUploadPage()),
        GetPage(
          name: Routes.branding,
          page: () => const BrandingPage(),
          binding: BindingsBuilder(() => Get.lazyPut(BrandingController.new)),
        ),
        GetPage(
          name: Routes.createVoucher,
          page: () => const CreateVoucherPage(),
          binding: BindingsBuilder(
            () => Get.lazyPut(CreateVoucherController.new),
          ),
        ),
      ],
    );
  }
}

abstract class Routes {
  static const splash = '/';
  static const login = '/login';
  static const verifyLogin = '/login/verify';
  static const shell = '/app';
  static const voucher = '/voucher';
  static const createVoucher = '/voucher/new';
  static const branding = '/branding';
  static const bulkApprove = '/approvals/bulk';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const platformCompany = '/platform/company';

  // Inventory: pages pushed over the shell (arguments: the record's id, or
  // {'type': 'grn' | 'issue' | 'transfer'} for a new document).
  static const erpDocument = '/erp/document';
  static const erpDocumentNew = '/erp/document/new';
  static const erpProduct = '/erp/product';

  // Sales and Dispatch: pages pushed over the shell (arguments: the
  // record's id; the new-document pages take a map, see their pages).
  static const salesOrder = '/erp/sales/order';
  static const salesQuotation = '/erp/sales/quotation';
  static const salesInvoice = '/erp/sales/invoice';
  static const salesReceipt = '/erp/sales/receipt';
  static const salesCustomer = '/erp/sales/customer';
  static const salesDocumentNew = '/erp/sales/document/new';
  static const salesReceiptNew = '/erp/sales/receipt/new';
  static const dispatchLoading = '/erp/dispatch/loading-order';
  static const dispatchLoadingNew = '/erp/dispatch/loading-order/new';

  // Production, CRM and Documents: pages pushed over the shell (arguments:
  // the record's id; the new-record pages take an optional map).
  static const prdOrder = '/erp/production/order';
  static const prdOrderNew = '/erp/production/order/new';
  static const prdBom = '/erp/production/bom';
  static const crmLead = '/erp/crm/lead';
  static const crmLeadNew = '/erp/crm/lead/new';
  static const crmOpportunity = '/erp/crm/opportunity';
  static const crmActivityNew = '/erp/crm/activity/new';
  static const filesDocument = '/erp/files/document';
  static const filesUpload = '/erp/files/upload';

  // Procurement, Finance and Assets: pages pushed over the shell
  // (arguments: the record's id; the new-record pages take an optional map).
  static const prcRequisition = '/erp/procurement/requisition';
  static const prcRequisitionNew = '/erp/procurement/requisition/new';
  static const prcOrder = '/erp/procurement/order';
  static const prcInvoice = '/erp/procurement/invoice';
  static const prcPayment = '/erp/procurement/payment';
  static const prcSupplier = '/erp/procurement/supplier';
  static const finBank = '/erp/finance/bank';
  static const finJournal = '/erp/finance/journal';
  static const finCashbookEntry = '/erp/finance/cashbook/entry';
  static const finCashbookNew = '/erp/finance/cashbook/new';
  static const astAsset = '/erp/assets/asset';
  static const astRun = '/erp/assets/run';

  // Fleet and HR: pages pushed over the shell (arguments: the record's id,
  // or a map with 'id' and 'mine' where a driver or employee reads their own).
  static const erpFleetTrip = '/erp/fleet/trip';
  static const erpFleetVehicle = '/erp/fleet/vehicle';
  static const erpFleetFuelNew = '/erp/fleet/fuel/new';
  static const erpHrEmployee = '/erp/hr/employee';
  static const erpHrPayslip = '/erp/hr/payslip';
  static const erpHrPayrollRun = '/erp/hr/payroll-run';
  static const erpHrLeaveNew = '/erp/hr/leave/new';
}

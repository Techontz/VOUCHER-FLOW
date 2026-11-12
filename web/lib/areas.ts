import type { MessageKey } from "./i18n";
import type { NavItem } from "./nav";

/**
 * The systems a person chooses between on the launcher. Every menu entry
 * belongs to exactly one, and the sidebar shows only the entries of the one
 * that is open, so a company running fifteen modules still sees a short menu.
 */
export type AreaKey =
  | "vouchflow" | "inventory" | "sales" | "dispatch" | "procurement" | "finance" | "assets"
  | "production" | "fleet" | "hr" | "crm" | "files" | "settings" | "platform";

export type AreaCategory = "finance" | "sales" | "supply" | "people" | "productivity" | "admin";

/** Apps are grouped the way a business thinks about its work. */
export const CATEGORIES: { key: AreaCategory; label: MessageKey }[] = [
  { key: "finance", label: "catFinance" },
  { key: "sales", label: "catSales" },
  { key: "supply", label: "catSupply" },
  { key: "people", label: "catPeople" },
  { key: "productivity", label: "catProductivity" },
  { key: "admin", label: "catAdmin" },
];

export interface Area {
  key: AreaKey;
  category: AreaCategory;
  label: MessageKey;
  blurb: MessageKey;
  icon: string;
  /** The tile colour: one system colour per area, so each is recognisable at a glance. */
  tint: string;
  /** The company module that switches it on; areas without one are always available. */
  module?: string;
}

export const AREAS: Area[] = [
  { key: "vouchflow", category: "finance", label: "areaVouchflow", blurb: "areaVouchflowBlurb", icon: "ph-receipt", tint: "#0a84ff", module: "vouchflow" },
  { key: "inventory", category: "supply", label: "areaInventory", blurb: "areaInventoryBlurb", icon: "ph-package", tint: "#ff9f0a", module: "inventory" },
  { key: "sales", category: "sales", label: "areaSales", blurb: "areaSalesBlurb", icon: "ph-storefront", tint: "#30d158", module: "sales" },
  { key: "dispatch", category: "sales", label: "areaDispatch", blurb: "areaDispatchBlurb", icon: "ph-truck-trailer", tint: "#40c8e0", module: "dispatch" },
  { key: "procurement", category: "supply", label: "areaProcurement", blurb: "areaProcurementBlurb", icon: "ph-shopping-cart", tint: "#5e5ce6", module: "procurement" },
  { key: "finance", category: "finance", label: "areaFinance", blurb: "areaFinanceBlurb", icon: "ph-bank", tint: "#bf5af2", module: "accounting" },
  { key: "assets", category: "finance", label: "areaAssets", blurb: "areaAssetsBlurb", icon: "ph-buildings", tint: "#ac8e68", module: "assets" },
  { key: "production", category: "supply", label: "areaProduction", blurb: "areaProductionBlurb", icon: "ph-factory", tint: "#ff453a", module: "production" },
  { key: "fleet", category: "supply", label: "areaFleet", blurb: "areaFleetBlurb", icon: "ph-truck", tint: "#ffb340", module: "fleet" },
  { key: "hr", category: "people", label: "areaHr", blurb: "areaHrBlurb", icon: "ph-users-three", tint: "#ff375f", module: "hr" },
  { key: "crm", category: "sales", label: "areaCrm", blurb: "areaCrmBlurb", icon: "ph-handshake", tint: "#64d2ff", module: "crm" },
  { key: "files", category: "productivity", label: "areaFiles", blurb: "areaFilesBlurb", icon: "ph-folder-simple", tint: "#8e8e93", module: "documents" },
  { key: "settings", category: "admin", label: "areaSettings", blurb: "areaSettingsBlurb", icon: "ph-gear-six", tint: "#636366" },
  { key: "platform", category: "admin", label: "areaPlatform", blurb: "areaPlatformBlurb", icon: "ph-globe-hemisphere-east", tint: "#0a84ff" },
];

const ADMIN_HREFS = ["/employees", "/departments", "/settings", "/branding", "/subscription", "/audit", "/erp/setup", "/erp/roles"];

/** Path prefixes of ERP screens that belong to an area other than their module's. */
const PATH_AREAS: [string, AreaKey][] = [
  ["/erp/dispatch", "dispatch"],
  ["/erp/assets", "assets"],
  ["/erp/files", "files"],
  ["/erp/crm", "crm"],
];

const MODULE_AREA: Record<string, AreaKey> = {
  inventory: "inventory", sales: "sales", dispatch: "dispatch", procurement: "procurement",
  accounting: "finance", assets: "assets", production: "production", fleet: "fleet",
  hr: "hr", crm: "crm", documents: "files",
};

/** The area a menu entry belongs to. */
export function areaOf(item: Pick<NavItem, "href" | "erp">): AreaKey {
  const href = item.href;
  if (href.startsWith("/platform")) return "platform";
  if (ADMIN_HREFS.some((h) => href === h || href.startsWith(h + "/"))) return "settings";
  const byPath = PATH_AREAS.find(([prefix]) => href === prefix || href.startsWith(prefix + "/"));
  if (byPath) return byPath[1];
  if (item.erp) return MODULE_AREA[item.erp.module ?? "inventory"] ?? "inventory";
  return "vouchflow";
}

export function areaByKey(key: AreaKey): Area {
  return AREAS.find((a) => a.key === key) ?? AREAS[0];
}

export interface CreateAction {
  label: MessageKey;
  href: string;
  icon: string;
  /** The ERP permission it needs; VouchFlow's own creation follows the role instead. */
  permission?: string;
}

/**
 * What the top bar's + button creates, per app: the everyday documents of
 * that app, so someone in Inventory is offered a goods received note, not a
 * payment voucher.
 */
export const CREATE_ACTIONS: Partial<Record<AreaKey, CreateAction[]>> = {
  vouchflow: [{ label: "newVoucher", href: "/vouchers/new", icon: "ph-receipt" }],
  inventory: [
    { label: "erpDocGrn", href: "/erp/documents/new?type=grn", icon: "ph-arrow-square-in", permission: "inventory.receive" },
    { label: "erpDocIssue", href: "/erp/documents/new?type=issue", icon: "ph-arrow-square-out", permission: "inventory.issue" },
    { label: "erpDocTransfer", href: "/erp/documents/new?type=transfer", icon: "ph-arrows-left-right", permission: "inventory.transfer" },
    { label: "erpDocCount", href: "/erp/documents/new?type=count", icon: "ph-list-numbers", permission: "inventory.adjust" },
    { label: "erpNewProduct", href: "/erp/products?new=1", icon: "ph-package", permission: "inventory.manage" },
  ],
  sales: [
    { label: "createQuotation", href: "/erp/sales/quotations/new", icon: "ph-file-text", permission: "sales.quote" },
    { label: "createSalesOrder", href: "/erp/sales/orders/new", icon: "ph-shopping-bag", permission: "sales.order" },
    { label: "createReceipt", href: "/erp/sales/receipts/new", icon: "ph-hand-coins", permission: "sales.receipt" },
    { label: "createReturn", href: "/erp/sales/returns/new", icon: "ph-arrow-u-up-left", permission: "sales.return" },
  ],
  procurement: [
    { label: "createRequisition", href: "/erp/procurement/requisitions/new", icon: "ph-clipboard-text", permission: "procurement.request" },
    { label: "createRfq", href: "/erp/procurement/rfqs/new", icon: "ph-scales", permission: "procurement.quote" },
    { label: "createPurchaseOrder", href: "/erp/procurement/orders/new", icon: "ph-shopping-cart", permission: "procurement.order" },
    { label: "createSupplierInvoice", href: "/erp/procurement/invoices/new", icon: "ph-invoice", permission: "procurement.invoice" },
    { label: "createSupplierPayment", href: "/erp/procurement/payments/new", icon: "ph-money", permission: "procurement.pay" },
  ],
  finance: [
    { label: "createCashbookEntry", href: "/erp/finance/cashbook?new=1", icon: "ph-notebook", permission: "finance.cashbook" },
    { label: "createBankAccount", href: "/erp/finance/banks?new=1", icon: "ph-bank", permission: "finance.bank" },
  ],
  assets: [{ label: "createAsset", href: "/erp/assets/register?new=1", icon: "ph-buildings", permission: "assets.manage" }],
  production: [
    { label: "createProductionOrder", href: "/erp/production/orders/new", icon: "ph-factory", permission: "production.plan" },
    { label: "createBom", href: "/erp/production/boms/new", icon: "ph-tree-structure", permission: "production.manage" },
  ],
  fleet: [{ label: "createTrip", href: "/erp/fleet/trips/new", icon: "ph-path", permission: "fleet.trips" }],
  hr: [{ label: "createEmployee", href: "/erp/hr/employees?new=1", icon: "ph-user-plus", permission: "hr.manage" }],
  crm: [{ label: "createLead", href: "/erp/crm/leads", icon: "ph-user-focus", permission: "crm.manage" }],
  files: [{ label: "createUpload", href: "/erp/files", icon: "ph-upload-simple", permission: "documents.upload" }],
  settings: [{ label: "createInvite", href: "/employees", icon: "ph-user-plus" }],
};

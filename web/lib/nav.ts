import type { Role } from "./types";
import type { MessageKey } from "./i18n";
import type { ModuleKey, Permission } from "./erp";
import { MODULE_NAV } from "./modules";

export interface NavItem {
  href: string;
  label: MessageKey;
  /** A one-word label for the mobile tab bar, where two lines do not fit. */
  short?: MessageKey;
  icon: string;
  badge?: "pending" | "payments" | "notifications";
  /**
   * ERP entries only: shown when the company runs `module` and the caller
   * holds `permission`, read from the API's resolved configuration, so the
   * menu offers exactly what the API will answer.
   */
  erp?: { module?: ModuleKey; permission: Permission };
}

/**
 * Navigation per role, following the v2 design's NAV map.
 *
 * An employee is deliberately given no route into other people's data, and a
 * cashier lands on the payment queue rather than a dashboard, the menu matches
 * what the API will actually return for that role.
 */
const NAV: Record<Role, NavItem[]> = {
  employee: [
    { href: "/dashboard", label: "home", icon: "ph-house" },
    { href: "/vouchers", label: "myVouchers", short: "vouchers", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profile", icon: "ph-user" },
  ],
  hod: [
    { href: "/dashboard", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/vouchers", label: "deptRegister", short: "vouchers", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", short: "profile", icon: "ph-signature" },
  ],
  // A manager is department-bound like an HOD: approvals for their own department.
  manager: [
    { href: "/dashboard", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/approvals", label: "bulkApprove", short: "approvals", icon: "ph-checks" },
    { href: "/vouchers", label: "deptRegister", short: "vouchers", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", short: "profile", icon: "ph-signature" },
  ],
  ceo: [
    { href: "/dashboard", label: "finalApprovals", short: "approvals", icon: "ph-seal-check", badge: "pending" },
    { href: "/approvals", label: "bulkApprove", short: "approvals", icon: "ph-checks" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", short: "profile", icon: "ph-signature" },
  ],
  cashier: [
    { href: "/dashboard", label: "paymentQueue", short: "payments", icon: "ph-wallet", badge: "payments" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profile", icon: "ph-user" },
  ],
  finance: [
    { href: "/dashboard", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/approvals", label: "bulkApprove", short: "approvals", icon: "ph-checks" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt" },
    { href: "/payments", label: "paymentQueue", short: "payments", icon: "ph-wallet", badge: "payments" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", short: "profile", icon: "ph-signature" },
  ],
  director: [
    { href: "/dashboard", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/approvals", label: "bulkApprove", short: "approvals", icon: "ph-checks" },
    { href: "/vouchers", label: "voucherRegister", short: "vouchers", icon: "ph-receipt" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/notifications", label: "notifications", icon: "ph-bell", badge: "notifications" },
    { href: "/profile", label: "profileSig", short: "profile", icon: "ph-signature" },
  ],
  company_admin: [
    { href: "/dashboard", label: "dashboard", icon: "ph-squares-four" },
    { href: "/vouchers", label: "vouchers", icon: "ph-receipt" },
    { href: "/vouchers/new", label: "createVoucher", icon: "ph-plus-circle" },
    { href: "/approvals", label: "approvals", icon: "ph-list-checks", badge: "pending" },
    { href: "/payments", label: "paymentQueue", short: "payments", icon: "ph-wallet", badge: "payments" },
    { href: "/employees", label: "employees", icon: "ph-users-three" },
    { href: "/departments", label: "departments", icon: "ph-buildings" },
    { href: "/reports", label: "reports", icon: "ph-chart-line" },
    { href: "/subscription", label: "subscription", icon: "ph-crown-simple" },
    { href: "/branding", label: "branding", icon: "ph-palette" },
    { href: "/audit", label: "auditLogs", short: "auditLogs", icon: "ph-scroll" },
    { href: "/settings", label: "settings", icon: "ph-gear" },
  ],
  // The platform operator: profile and notifications sit in the user menu and the top bar.
  super_admin: [
    { href: "/dashboard", label: "overview", icon: "ph-squares-four" },
    { href: "/platform/companies", label: "companies", short: "companies", icon: "ph-buildings" },
    { href: "/platform/subscriptions", label: "pfSubscriptions", short: "pfSubscriptionsShort", icon: "ph-arrows-clockwise" },
    { href: "/platform/plans", label: "pfPlans", short: "pfPlans", icon: "ph-crown-simple" },
    { href: "/platform/payments", label: "payments", short: "payments", icon: "ph-credit-card" },
    { href: "/platform/users", label: "users", short: "users", icon: "ph-users-three" },
    { href: "/audit", label: "auditLogs", short: "auditLogs", icon: "ph-scroll" },
    { href: "/platform/settings", label: "settings", icon: "ph-gear" },
  ],
};

/** The ERP modules, offered to every tenant role and filtered per caller in the shell. */
const ERP_NAV: NavItem[] = [
  { href: "/erp", label: "erpHome", short: "erpHomeShort", icon: "ph-squares-four", erp: { permission: "inventory.view" } },
  { href: "/erp/products", label: "erpProducts", icon: "ph-package", erp: { module: "inventory", permission: "inventory.view" } },
  { href: "/erp/stock", label: "erpStock", icon: "ph-stack", erp: { module: "inventory", permission: "inventory.view" } },
  { href: "/erp/documents", label: "erpDocuments", short: "erpDocumentsShort", icon: "ph-clipboard-text", erp: { module: "inventory", permission: "inventory.view" } },
  { href: "/erp/warehouses", label: "erpWarehouses", icon: "ph-warehouse", erp: { module: "inventory", permission: "inventory.view" } },
  { href: "/erp/catalogue", label: "erpCatalogue", icon: "ph-ruler", erp: { module: "inventory", permission: "inventory.manage" } },
  { href: "/erp/customers", label: "erpCustomers", icon: "ph-users", erp: { module: "sales", permission: "customers.view" } },
  { href: "/erp/suppliers", label: "erpSuppliers", icon: "ph-truck", erp: { module: "procurement", permission: "suppliers.view" } },
  { href: "/erp/accounts", label: "erpAccounts", icon: "ph-calculator", erp: { module: "accounting", permission: "accounting.view" } },
  // Later modules' entries, each from its own file in lib/modules.
  ...MODULE_NAV,
  { href: "/erp/setup", label: "erpSetup", icon: "ph-sliders", erp: { permission: "erp.configure" } },
  { href: "/erp/roles", label: "erpRoles", icon: "ph-shield-check", erp: { permission: "roles.manage" } },
];

export function navFor(role: Role | string): NavItem[] {
  const base = NAV[role as Role] ?? NAV.employee;
  return role === "super_admin" ? base : [...base, ...ERP_NAV];
}

/**
 * Whether an ERP entry is open to this caller. The overview is the one entry
 * not tied to a module: it opens for anyone who may see any ERP area.
 */
export function erpEntryVisible(
  item: NavItem,
  config: { is_set_up: boolean; modules: string[]; permissions: string[] } | null,
): boolean {
  if (!item.erp) return true;
  if (!config) return false;
  const may = (p: string) => config.permissions.includes(p);
  if (item.href === "/erp/setup") return may("erp.configure");
  if (!config.is_set_up) return false;
  if (item.href === "/erp") return config.permissions.some((p) => p.endsWith(".view"));
  return (!item.erp.module || config.modules.includes(item.erp.module)) && may(item.erp.permission);
}

/** The five slots on the mobile tab bar; creating a voucher is the FAB instead. */
export function mobileNavFor(role: Role): NavItem[] {
  const items = navFor(role);
  const home = items[0];
  const rest = items.filter((i) => i !== home && i.href !== "/vouchers/new");
  return [home, ...rest].slice(0, 5);
}

export function isAdminRole(role: Role): boolean {
  return role === "company_admin" || role === "super_admin";
}

/** Roles whose step in a workflow can release money. */
export function isPayingRole(role: Role): boolean {
  return role === "cashier" || role === "finance";
}

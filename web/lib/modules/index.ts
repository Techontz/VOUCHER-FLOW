import * as sales from "./sales";
import * as procurement from "./procurement";
import * as fleet from "./fleet";
import * as hr from "./hr";
import * as production from "./production";
import * as finance from "./finance";
import * as crm from "./crm";
import * as integration from "./integration";

/*
 * Every ERP module added after the core, one file each, so a module's menu
 * and copy never share a file with another's.
 */

export const MODULE_MESSAGES = {
  ...sales.messages,
  ...procurement.messages,
  ...fleet.messages,
  ...hr.messages,
  ...production.messages,
  ...finance.messages,
  ...crm.messages,
  ...integration.messages,
} as const;

export const MODULE_NAV = [
  ...sales.nav,
  ...procurement.nav,
  ...fleet.nav,
  ...hr.nav,
  ...production.nav,
  ...finance.nav,
  ...crm.nav,
  ...integration.nav,
];

import type { NavItem } from "../nav";

/**
 * VouchFlow and ERP integration.
 *
 * This module's menu entries and its English + Swahili copy. Spread into the
 * main menu and dictionary by lib/modules/index.ts, so every key here is a
 * MessageKey like any other.
 */
export const messages = {} as const satisfies Record<string, readonly [string, string]>;

export const nav: NavItem[] = [];

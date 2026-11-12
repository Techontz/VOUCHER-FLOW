"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { useApp } from "@/lib/app-context";
import type { MessageKey } from "@/lib/i18n";
import { type AccountType, type DocumentStatus, type DocumentType, type ModuleKey, type Permission, type ProductType, statusTone, useErp } from "@/lib/erp";
import { Badge, EmptyState, Icon, LoadingBlock } from "@/components/ui";

/*
 * Pieces every ERP screen shares. The gate is the important one: it settles
 * loading, a company that has not set up, a module that is off and a role
 * without the permission, once, the same way on every screen, so a page
 * body only ever renders for someone the API will actually answer.
 */

export function ErpGate({ module, permission, children }: { module?: ModuleKey; permission?: Permission; children: ReactNode }) {
  const { t, user } = useApp();
  const { config, loading, can, has } = useErp();

  if (loading) return <LoadingBlock rows={5} />;

  if (!config?.is_set_up) {
    const admin = user?.role === "company_admin";
    return (
      <EmptyState
        icon="ph-rocket-launch"
        title={t("erpNotSetUpTitle")}
        body={admin ? t("erpNotSetUpBody") : t("erpNotSetUpOthers")}
        action={admin ? <Link className="btn btn-primary" href="/erp/setup"><Icon name="ph-sparkle" size={18} /> {t("erpOpenSetup")}</Link> : undefined}
      />
    );
  }

  if (module && !has(module)) {
    return (
      <EmptyState icon="ph-toggle-left" title={t("erpModuleOff")}
        action={can("erp.configure") ? <Link className="btn btn-secondary" href="/erp/setup">{t("erpOpenSetup")}</Link> : undefined} />
    );
  }

  if (permission && !can(permission)) return <EmptyState icon="ph-lock-simple" title={t("erpNoAccess")} />;

  return <>{children}</>;
}

export const DOC_LABEL: Record<DocumentType, MessageKey> = {
  grn: "erpDocGrn", issue: "erpDocIssue", transfer: "erpDocTransfer",
  adjustment: "erpDocAdjustment", count: "erpDocCount", opening: "erpDocOpening",
};

export const DOC_HINT: Record<DocumentType, MessageKey> = {
  grn: "erpDocGrnHint", issue: "erpDocIssueHint", transfer: "erpDocTransferHint",
  adjustment: "erpDocAdjustmentHint", count: "erpDocCountHint", opening: "erpDocOpeningHint",
};

const STATUS_LABEL: Record<DocumentStatus, MessageKey> = {
  draft: "erpStatusDraft", posted: "erpStatusPosted", cancelled: "erpStatusCancelled", reversed: "erpStatusReversed",
};

export const PRODUCT_TYPE_LABEL: Record<ProductType, MessageKey> = {
  stock: "erpTypeStock", service: "erpTypeService", raw_material: "erpTypeRaw",
  finished_good: "erpTypeFinished", packaging: "erpTypePackaging",
};

export const ACCOUNT_TYPE_LABEL: Record<AccountType, MessageKey> = {
  asset: "erpTypeAsset", liability: "erpTypeLiability", equity: "erpTypeEquity", income: "erpTypeIncome", expense: "erpTypeExpense",
};

export const WAREHOUSE_TYPE_LABEL: Record<string, MessageKey> = {
  warehouse: "erpWhTypeWarehouse", depot: "erpWhTypeDepot", shop: "erpWhTypeShop",
  branch: "erpWhTypeBranch", production: "erpWhTypeProduction",
};

export function DocStatus({ status }: { status: DocumentStatus }) {
  const { t } = useApp();
  return <Badge tone={statusTone(status)} dot>{t(STATUS_LABEL[status])}</Badge>;
}

/** A figure that reads as an in/out movement: green +, red −. */
export function SignedQty({ value }: { value: string | number }) {
  const n = Number(value);
  return (
    <span className="tnum" style={{ color: n < 0 ? "var(--st-bad-fg)" : n > 0 ? "var(--st-ok-fg)" : undefined, fontWeight: 600 }}>
      {n > 0 ? "+" : n < 0 ? "−" : ""}{Math.abs(n).toLocaleString("en-US", { maximumFractionDigits: 4 })}
    </span>
  );
}

/** Replaces {n}-style placeholders in a translated string. */
export function fill(text: string, values: Record<string, string | number>): string {
  return Object.entries(values).reduce((s, [k, v]) => s.split(`{${k}}`).join(String(v)), text);
}

/** A segmented filter row, for list screens. */
export function FilterChips<T extends string>({ value, onChange, items }: {
  value: T; onChange: (v: T) => void; items: { value: T; label: string; count?: number }[];
}) {
  return (
    <div className="seg" role="group">
      {items.map((item) => (
        <button key={item.value} type="button" aria-pressed={value === item.value} onClick={() => onChange(item.value)}>
          {item.label}{item.count !== undefined ? <span className="tnum" style={{ opacity: .7, marginLeft: 6 }}>{item.count}</span> : null}
        </button>
      ))}
    </div>
  );
}

/** A plain labelled checkbox row, used for flags on ERP forms. */
export function Check({ label, hint, checked, onChange, disabled }: {
  label: string; hint?: string; checked: boolean; onChange: (v: boolean) => void; disabled?: boolean;
}) {
  return (
    <label className="erp-check" data-disabled={disabled ? "" : undefined}>
      <input type="checkbox" checked={checked} disabled={disabled} onChange={(e) => onChange(e.target.checked)} />
      <span>
        <span className="erp-check-label">{label}</span>
        {hint && <span className="erp-check-hint">{hint}</span>}
      </span>
    </label>
  );
}

"use client";

import { useApp } from "@/lib/app-context";
import { amount, qty } from "@/lib/erp";
import type { Requirement } from "@/lib/production-api";
import { Badge } from "@/components/ui";

/**
 * What an order needs of each component. Planning shows need against stock;
 * on a running order it also shows what has been issued and, once output is
 * recorded, any usage beyond the recipe's allowance.
 */
export function RequirementTable({ rows, planning, produced }: { rows: Requirement[]; planning?: boolean; produced?: boolean }) {
  const { t } = useApp();

  return (
    <div className="vf-table-wrap">
      <table className="table vf-table">
        <thead>
          <tr>
            <th>{t("prdComponent")}</th>
            <th className="num">{t("prdStandardQty")}</th>
            <th className="num">{t("prdAllowance")}</th>
            <th className="num">{t("prdRequired")}</th>
            {!planning && <th className="num">{t("prdIssued")}</th>}
            {!planning && <th className="num">{t("prdRemaining")}</th>}
            <th className="num">{t("prdAvailable")}</th>
            {produced && <th className="num">{t("prdBeyondAllowance")}</th>}
            <th>{t("erpStatus")}</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.product_id}>
              <td>
                <span className="erp-cell-title">{r.product.name}</span>
                <span className="erp-cell-sub tnum">{r.product.sku}{r.product.track_batches && r.batches.length > 0 ? ` · ${r.batches.length} ${t("prdBatchesHeld")}` : ""}</span>
              </td>
              <td className="num">{qty(r.standard_quantity)} <span className="erp-muted">{r.product.unit}</span></td>
              <td className="num">{qty(r.allowance_quantity)} <span className="erp-muted">({qty(r.scrap_percent)}%)</span></td>
              <td className="num">{qty(r.required_quantity)}</td>
              {!planning && <td className="num">{qty(r.issued_quantity)}</td>}
              {!planning && <td className="num">{qty(r.remaining_quantity)}</td>}
              <td className="num">{qty(r.available_quantity)}</td>
              {produced && (
                <td className="num">
                  {r.excess_quantity > 0.00005
                    ? <span style={{ color: "var(--st-bad-fg)" }}>{qty(r.excess_quantity)}<span className="erp-cell-sub">{amount(r.excess_value)}</span></span>
                    : <span className="erp-muted">{qty(Math.max(0, r.excess_quantity))}</span>}
                </td>
              )}
              <td>
                {planning || r.remaining_quantity > 0.00005
                  ? (r.sufficient ? <Badge tone="ok" dot>{t("prdEnough")}</Badge> : <Badge tone="bad" dot>{`${t("prdShort")} ${qty(r.shortfall_quantity)}`}</Badge>)
                  : <Badge tone="neutral" dot>{t("prdFullyIssued")}</Badge>}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

"use client";

import Link from "next/link";
import { useApp } from "@/lib/app-context";
import { amount, qty, type StockMovement } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { Badge } from "@/components/ui";
import { SignedQty } from "@/components/erp-ui";

/** The ledger as a table: date, reference, where, signed quantity, balance after. Shared with the stock screen. */
export function MovementTable({ rows, showProduct = false }: { rows: StockMovement[]; showProduct?: boolean }) {
  const { t, locale } = useApp();
  return (
    <div className="vf-table-wrap">
      <table className="table vf-table">
        <thead>
          <tr>
            <th>{t("erpDate")}</th><th>{t("erpReference")}</th>{showProduct && <th>{t("erpProduct")}</th>}
            <th>{t("erpWarehouse")}</th><th>{t("erpType")}</th><th className="num">{t("erpQuantity")}</th>
            <th className="num">{t("erpUnitCost")}</th><th className="num">{t("erpBalanceAfter")}</th><th>{t("erpBy")}</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((m) => (
            <tr key={m.id}>
              <td className="tnum">{formatDate(m.movement_date, locale)}</td>
              <td className="tnum">
                {m.stock_document_id ? <Link href={`/erp/documents/${m.stock_document_id}`}>{m.reference}</Link> : m.reference}
              </td>
              {showProduct && <td>{m.product?.name}<span className="erp-cell-sub tnum">{m.product?.sku}</span></td>}
              <td>{m.warehouse?.name}{m.batch_number ? <span className="erp-cell-sub tnum">{m.batch_number}</span> : null}</td>
              <td><Badge>{m.type.replace("_", " ")}</Badge></td>
              <td className="num"><SignedQty value={m.quantity} /></td>
              <td className="num">{amount(m.unit_cost)}</td>
              <td className="num">{qty(m.balance_after)}</td>
              <td>{m.creator?.name ?? "-"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

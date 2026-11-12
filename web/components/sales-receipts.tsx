"use client";

import Link from "next/link";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { METHOD_LABEL, type Receipt } from "@/lib/sales-api";
import { Icon } from "@/components/ui";
import { fill } from "@/components/erp-ui";
import { type Act, Money, SalesBadge } from "@/components/sales-ui";

/**
 * Receipts as a table, with verify and reject for finance. The person who
 * recorded a receipt is shown a note instead of the buttons: the API refuses
 * them anyway, someone else must verify.
 */
export function ReceiptRows({ rows, onAct }: { rows: Receipt[]; onAct?: (act: Act) => void }) {
  const { t, locale, user } = useApp();
  const { can } = useErp();
  return (
    <div className="vf-table-wrap">
      <table className="table vf-table">
        <thead><tr><th>{t("salReceipt")}</th><th>{t("salCustomer")}</th><th>{t("erpDate")}</th><th>{t("salMethod")}</th><th>{t("salAppliedTo")}</th><th className="num">{t("salAmount")}</th><th>{t("erpStatus")}</th>{onAct && <th />}</tr></thead>
        <tbody>
          {rows.map((r) => {
            const mine = user && String(r.created_by) === String(user.id);
            return (
              <tr key={r.id}>
                <td><span className="erp-cell-title tnum">{r.number}</span><span className="erp-cell-sub">{r.creator?.name}{r.verifier ? ` · ${r.verifier.name}` : ""}</span></td>
                <td>{r.customer?.name}</td>
                <td className="tnum">{formatDate(r.receipt_date, locale)}</td>
                <td>{t(METHOD_LABEL[r.method])}{r.reference ? <span className="erp-cell-sub tnum">{r.reference}</span> : null}<span className="erp-cell-sub">{r.account?.code} {r.account?.name}</span></td>
                <td>{r.allocations?.map((a) => <Link key={a.id} className="erp-cell-sub tnum" href={`/erp/sales/invoices/${a.sales_invoice_id}`}>{a.invoice?.number}: <Money value={a.amount} /></Link>)}</td>
                <td className="num"><Money value={r.amount} strong /></td>
                <td><SalesBadge status={r.status} />{r.rejection_reason && <span className="erp-cell-sub">{r.rejection_reason}</span>}</td>
                {onAct && (
                  <td className="num">
                    {r.status === "recorded" && can("dispatch.verify") && (mine
                      ? <span className="erp-muted">{t("salVerifyOther")}</span>
                      : <span className="sal-row-actions">
                        <button className="btn btn-secondary btn-sm" onClick={() => onAct({ key: "reject", path: `/erp/sales/receipts/${r.id}/reject`, label: t("salReject"), icon: "ph-x-circle", tone: "warn", title: fill(t("salRejectReceiptQ"), { number: r.number }), reason: { label: t("erpReason"), required: true } })}>{t("salReject")}</button>
                        <button className="btn btn-primary btn-sm" onClick={() => onAct({ key: "verify", path: `/erp/sales/receipts/${r.id}/verify`, label: t("salVerify"), icon: "ph-shield-check", title: fill(t("salVerifyQ"), { number: r.number }), sub: t("salVerifySub") })}><Icon name="ph-shield-check" size={15} /> {t("salVerify")}</button>
                      </span>)}
                  </td>
                )}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}


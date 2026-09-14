"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { money } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Figure, FigureStrip } from "@/components/app-ui";
import { VoucherList, VoucherTable } from "@/components/voucher-bits";
import type { Paginated, Voucher } from "@/lib/types";

type Filter = "all" | "bank" | "cash";

/**
 * The payment queue.
 *
 * Everything here has already cleared the approval workflow. The person with
 * the pay capability releases the funds and records the reference — no
 * approval decision is made on this screen. Paying happens on the voucher,
 * behind a confirmation that restates the amount and method.
 */
export default function PaymentsPage() {
  const { t, company } = useApp();
  const [due, setDue] = useState<Voucher[] | null>(null);
  const [paid, setPaid] = useState<Voucher[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<Filter>("all");

  const load = useCallback(() => {
    setError(null);
    Promise.all([
      api.get<Paginated<Voucher>>("/vouchers", { status: "approved", per_page: 50 }),
      api.get<Paginated<Voucher>>("/vouchers", { status: "paid", per_page: 12 }),
    ])
      .then(([queue, settled]) => { setDue(queue.data); setPaid(settled.data); })
      .catch((err) => setError(err.message));
  }, []);

  useEffect(load, [load]);

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!due) return <LoadingBlock rows={5} />;

  const cash = due.filter((v) => v.kind === "cash");
  const bank = due.filter((v) => v.kind === "bank");
  const total = (rows: Voucher[]) => rows.reduce((sum, v) => sum + v.amount, 0);
  const shown = filter === "bank" ? bank : filter === "cash" ? cash : due;

  return (
    <div className="app-page">
      <PageHeader
        title={`${due.length} ${due.length === 1 ? t("voucherWord") : t("vouchersWord")} ${t("awaitingPayment").toLowerCase()}`}
        sub={t("payNote")}
        actions={<Link className="btn btn-secondary" href="/vouchers"><Icon name="ph-receipt" size={15} /> {t("voucherRegister")}</Link>}
      />

      <div className="app-section">
        <FigureStrip>
          <Figure label={t("dueToday")} value={money(total(due), company?.currency)} sub={`${due.length} ${due.length === 1 ? t("voucherWord") : t("vouchersWord")}`} tone={due.length ? "info" : undefined} />
          <Figure label={t("bankTransfers")} value={money(total(bank), company?.currency)} sub={`${bank.length} ${t("bankVoucher").toLowerCase()}`} />
          <Figure label={t("cashDue")} value={money(total(cash), company?.currency)} sub={`${cash.length} ${t("cashVoucher").toLowerCase()}`} />
          <Figure label={t("paidAct")} value={money(total(paid), company?.currency)} sub={`${paid.length} ${t("paymentHistoryH").toLowerCase()}`} tone="ok" />
        </FigureStrip>
      </div>

      <div className="app-stack">
        <section className="vf-panel" aria-labelledby="due-title">
          <div className="vf-panel-head">
            <div className="vf-panel-head-main app-panel-title">
              <h2 id="due-title">{t("awaitingPayment")}</h2>
              <span className="vf-count">{shown.length}</span>
            </div>
            <div className="seg seg-sm" role="tablist" aria-label={t("voucherFormat")}>
              {([["all", t("all")], ["bank", t("bank")], ["cash", t("cash")]] as const).map(([key, label]) => (
                <button key={key} type="button" role="tab" aria-selected={filter === key} onClick={() => setFilter(key)}>{label}</button>
              ))}
            </div>
          </div>
          {shown.length > 0 ? (
            <>
              <VoucherList vouchers={shown} bare />
              <div className="app-panel-foot"><Icon name="ph-info" size={15} /><span>{t("approveNextNote")}</span></div>
            </>
          ) : (
            <EmptyState tone="ok" icon="ph-check-circle" title={t("nothingAwaiting")} body={t("nothingAwaitingBody")}
              action={<Link className="btn btn-secondary" href="/vouchers">{t("voucherRegister")}</Link>} />
          )}
        </section>

        {paid.length > 0 && (
          <section className="vf-panel" aria-labelledby="history-title">
            <div className="vf-panel-head">
              <div className="vf-panel-head-main app-panel-title"><h2 id="history-title">{t("paymentHistoryH")}</h2><span className="vf-count">{paid.length}</span></div>
              <Link className="btn btn-ghost btn-sm" href="/reports">{t("reports")} <Icon name="ph-arrow-right" size={13} /></Link>
            </div>
            <VoucherTable vouchers={paid} bare />
          </section>
        )}
      </div>
    </div>
  );
}

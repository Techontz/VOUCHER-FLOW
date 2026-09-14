"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { compactMoney } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, Note, PageHeader, SectionTitle, StatBlock, StatGrid } from "@/components/ui";
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
    <div className="vf-dashboard">
      <PageHeader
        kicker={t("paymentQueue")}
        title={`${due.length} ${due.length === 1 ? t("voucherWord") : t("vouchersWord")} ${t("awaitingPayment").toLowerCase()}`}
        sub={t("payNote")}
        actions={<Link className="btn btn-secondary" href="/vouchers"><Icon name="ph-receipt" size={17} /> {t("voucherRegister")}</Link>}
      />

      <section className="vf-dash-section">
        <StatGrid>
          <StatBlock label={t("dueToday")} value={String(due.length)} sub={compactMoney(total(due), company?.currency)} icon="ph-wallet" tone="info" />
          <StatBlock label={t("bankTransfers")} value={compactMoney(total(bank), company?.currency)} sub={`${bank.length} ${t("bankVoucher").toLowerCase()}`} icon="ph-bank" />
          <StatBlock label={t("cashDue")} value={compactMoney(total(cash), company?.currency)} sub={`${cash.length} ${t("cashVoucher").toLowerCase()}`} icon="ph-money" />
          <StatBlock label={t("paidAct")} value={String(paid.length)} sub={compactMoney(total(paid), company?.currency)} icon="ph-check-circle" tone="ok" />
        </StatGrid>
      </section>

      <section className="vf-dash-section">
        <SectionTitle
          count={shown.length}
          actions={
            <div className="seg seg-sm" role="tablist" aria-label={t("voucherFormat")}>
              {([["all", t("all")], ["bank", t("bank")], ["cash", t("cash")]] as const).map(([key, label]) => (
                <button key={key} type="button" role="tab" aria-selected={filter === key} onClick={() => setFilter(key)}>{label}</button>
              ))}
            </div>
          }
        >
          {t("awaitingPayment")}
        </SectionTitle>

        {shown.length > 0 ? (
          <>
            <VoucherList vouchers={shown} />
            <div style={{ marginTop: 12 }}><Note>{t("approveNextNote")}</Note></div>
          </>
        ) : (
          <div className="vf-panel">
            <EmptyState tone="ok" icon="ph-check-circle" title={t("nothingAwaiting")} body={t("nothingAwaitingBody")}
              action={<Link className="btn btn-secondary" href="/vouchers">{t("voucherRegister")}</Link>} />
          </div>
        )}
      </section>

      {paid.length > 0 && (
        <section className="vf-dash-section">
          <SectionTitle>{t("paymentHistoryH")}</SectionTitle>
          <VoucherTable vouchers={paid} />
        </section>
      )}
    </div>
  );
}

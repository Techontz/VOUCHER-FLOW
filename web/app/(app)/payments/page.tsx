"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { money, relativeTime } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, StatBlock } from "@/components/ui";
import { KindChip, VoucherList, VoucherTable } from "@/components/voucher-bits";
import type { Paginated, Voucher } from "@/lib/types";

type Filter = "all" | "bank" | "cash";
type View = "due" | "paid";

/**
 * The payment queue.
 *
 * Everything here has already cleared the approval workflow. The person with
 * the pay capability releases the funds and records the reference — no
 * approval decision is made on this screen. Paying happens on the voucher,
 * behind a confirmation that restates the amount and method; "Pay" opens the
 * voucher with that confirmation already up.
 */
export default function PaymentsPage() {
  const { t, company, locale } = useApp();
  const router = useRouter();
  const sw = locale === "sw";
  const [due, setDue] = useState<Voucher[] | null>(null);
  const [paid, setPaid] = useState<Voucher[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<Filter>("all");
  const [view, setView] = useState<View>("due");

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
  // Oldest approval first: what has waited longest is paid first.
  const queue = [...shown].sort((a, b) => String(a.approved_at ?? "").localeCompare(String(b.approved_at ?? "")));
  const count = (n: number) => `${n} ${n === 1 ? t("voucherWord") : t("vouchersWord")}`;

  return (
    <div className="app-page">
      <PageHeader
        title={t("paymentQueue")}
        sub={sw ? "Vocha zilizoidhinishwa zinazosubiri kulipwa, za zamani kwanza" : "Approved vouchers waiting to be paid, oldest first"}
        actions={<Link className="btn btn-secondary btn-sm" href="/vouchers"><Icon name="ph-receipt" size={15} /> {t("voucherRegister")}</Link>}
      />

      <section className="app-section">
        <div className="vf-kpis" style={{ gridTemplateColumns: "repeat(4, minmax(0, 1fr))" }}>
          <StatBlock label={t("awaitingPayment")} value={money(total(due), company?.currency)} sub={`${count(due.length)} · ${cash.length} ${t("cash").toLowerCase()}, ${bank.length} ${t("bank").toLowerCase()}`} icon="ph-wallet" tone={due.length ? "info" : "neutral"} />
          <StatBlock label={t("bankTransfers")} value={money(total(bank), company?.currency)} sub={count(bank.length)} icon="ph-bank" />
          <StatBlock label={t("cashDue")} value={money(total(cash), company?.currency)} sub={count(cash.length)} icon="ph-money" />
          <StatBlock label={sw ? "Zilizolipwa karibuni" : "Recently paid"} value={money(total(paid), company?.currency)} sub={count(paid.length)} icon="ph-check-circle" tone="ok" />
        </div>
      </section>

      <div className="app-tabs" role="tablist" aria-label={t("paymentQueue")}>
        <button type="button" role="tab" aria-selected={view === "due"} onClick={() => setView("due")}>
          {t("awaitingPayment")}<span className="app-tabs-count tnum">{due.length}</span>
        </button>
        <button type="button" role="tab" aria-selected={view === "paid"} onClick={() => setView("paid")}>
          {t("paidAct")}<span className="app-tabs-count tnum">{paid.length}</span>
        </button>
      </div>

      {view === "due" ? (
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
          {queue.length > 0 ? (
            <>
              <div className="table-wrap vf-only-wide">
                <table className="table app-pay-table">
                  <thead>
                    <tr>
                      <th>{t("voucher")}</th>
                      <th>{t("payee")}</th>
                      <th>{sw ? "Aina" : "Kind"}</th>
                      <th>{sw ? "Iliidhinishwa" : "Approved"}</th>
                      <th className="num">{t("amount")}</th>
                      <th aria-label={sw ? "Kitendo" : "Action"} />
                    </tr>
                  </thead>
                  <tbody>
                    {queue.map((v, i) => (
                      <tr key={v.id} className="is-clickable" onClick={(e) => {
                        if ((e.target as HTMLElement).closest("a, button")) return;
                        router.push(`/vouchers/${v.id}`);
                      }}>
                        <td>
                          <Link href={`/vouchers/${v.id}`} className="app-mono app-pay-number">{v.number}</Link>
                          <span className="app-vt-sub">{v.department?.name}</span>
                        </td>
                        <td className="app-pay-payee">
                          <div className="app-vt-title">{v.payee}</div>
                          <div className="app-vt-meta">{v.purpose}</div>
                        </td>
                        <td><KindChip kind={v.kind} /></td>
                        <td className="app-vt-date">{relativeTime(v.approved_at, locale)}</td>
                        <td className="num app-vt-amount">{v.amount_text}</td>
                        <td className="app-row-actions">
                          {v.actions?.pay
                            ? <Link className={`btn btn-sm ${i === 0 ? "btn-primary" : "btn-secondary"}`} href={`/vouchers/${v.id}?action=pay`}>{sw ? "Lipa" : "Pay"}</Link>
                            : <Link className="btn btn-ghost btn-sm" href={`/vouchers/${v.id}`}>{t("details")}</Link>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <div className="vf-only-narrow"><VoucherList vouchers={queue} bare /></div>
              <div className="app-panel-foot"><Icon name="ph-info" size={15} /><span>{t("payNote")}</span></div>
            </>
          ) : (
            <EmptyState tone="ok" icon="ph-wallet" title={t("nothingAwaiting")} body={t("nothingAwaitingBody")}
              action={<Link className="btn btn-secondary btn-sm" href="/vouchers">{t("voucherRegister")}</Link>} />
          )}
        </section>
      ) : (
        <section className="vf-panel" aria-labelledby="history-title">
          <div className="vf-panel-head">
            <div className="vf-panel-head-main app-panel-title"><h2 id="history-title">{t("paymentHistoryH")}</h2><span className="vf-count">{paid.length}</span></div>
            <Link className="btn btn-ghost btn-sm" href="/reports">{t("reports")} <Icon name="ph-arrow-right" size={13} /></Link>
          </div>
          {paid.length > 0
            ? <VoucherTable vouchers={paid} bare />
            : <EmptyState icon="ph-receipt" title={sw ? "Hakuna malipo bado" : "No payments yet"} body={sw ? "Vocha zilizolipwa zitaonekana hapa." : "Paid vouchers will appear here."} />}
        </section>
      )}
    </div>
  );
}

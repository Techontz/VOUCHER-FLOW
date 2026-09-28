"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { money } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { Figure, FigureStrip } from "@/components/app-ui";
import { ExportMenu, VoucherList, VoucherTable } from "@/components/voucher-bits";
import type { Paginated, Voucher } from "@/lib/types";

type Filter = "all" | "bank" | "cash";

/** A count and a value, read from a list's pagination total and meta.total_amount. */
interface Tally { count: number; amount: number }

const tally = (page: Paginated<Voucher>): Tally => ({
  count: page.meta?.total ?? page.data.length,
  amount: page.meta?.total_amount ?? 0,
});

/** What is still owed on one voucher: its balance, or all of it before any payment. */
const owed = (v: Voucher) => v.balance ?? v.amount;

/** Count and outstanding value of the queue rows, optionally of one format. */
function owedTally(rows: Voucher[], kind?: "bank" | "cash"): Tally {
  const picked = kind ? rows.filter((v) => v.kind === kind) : rows;
  return { count: picked.length, amount: picked.reduce((sum, v) => sum + owed(v), 0) };
}

/**
 * Every voucher in the payment queue, paged through at the API's maximum.
 *
 * The list's meta.total_amount sums approved amounts, which overstates what is
 * owed once a voucher has been part-paid — 10,000,000 approved, 9,000,000
 * released, 1,000,000 outstanding. Until the list carries a balance total, the
 * queue figures are summed from each voucher's own balance. The queue is
 * short-lived work, so this is a page or two, not the whole register.
 */
async function wholeQueue(): Promise<Voucher[]> {
  const first = await api.get<Paginated<Voucher>>("/vouchers", { status: "approved", per_page: 100, page: 1 });
  const last = first.meta?.last_page ?? 1;
  if (last <= 1) return first.data;
  const rest = await Promise.all(
    Array.from({ length: last - 1 }, (_, i) =>
      api.get<Paginated<Voucher>>("/vouchers", { status: "approved", per_page: 100, page: i + 2 })),
  );
  return [first, ...rest].flatMap((page) => page.data);
}

/** First and last day of the current month, as the API's date filters expect. */
function thisMonth(): { from: string; to: string } {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  const last = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
  const ym = `${now.getFullYear()}-${pad(now.getMonth() + 1)}`;
  return { from: `${ym}-01`, to: `${ym}-${pad(last)}` };
}

/**
 * The payment queue.
 *
 * Everything here has already cleared the approval workflow. The person with
 * the pay capability releases the funds and records the reference — no
 * approval decision is made on this screen. Paying happens on the voucher,
 * behind a confirmation that restates the amount and method.
 *
 * Every figure covers the whole set, never just the rows that happen to be on
 * screen. What is awaiting payment is counted by what is still owed, so a
 * part-paid voucher counts for its balance, not its full approved amount.
 */
/** "1 bank voucher", "13 bank vouchers" — in either language. */
function usePlural() {
  const { locale } = useApp();
  return (n: number, kind: "bank" | "cash") => locale === "sw"
    ? `${n} ${kind === "bank" ? "vocha za benki" : "vocha za taslimu"}`.replace(/^1 vocha za (\w+)/, "1 vocha ya $1")
    : `${n} ${kind} ${n === 1 ? "voucher" : "vouchers"}`;
}

export default function PaymentsPage() {
  const { t, company } = useApp();
  const kindCount = usePlural();
  const [filter, setFilter] = useState<Filter>("all");
  const [page, setPage] = useState(1);
  const [due, setDue] = useState<Paginated<Voucher> | null>(null);
  const [paid, setPaid] = useState<Paginated<Voucher> | null>(null);
  const [figures, setFigures] = useState<{ due: Tally; bank: Tally; cash: Tally; paidMonth: Tally } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const kind = filter === "all" ? "" : filter;

  const loadFigures = useCallback(() => {
    const month = thisMonth();
    Promise.all([
      wholeQueue(),
      api.get<Paginated<Voucher>>("/vouchers", { status: "paid", paid_from: month.from, paid_to: month.to, per_page: 1 }),
    ])
      .then(([queue, paidMonth]) => setFigures({
        due: owedTally(queue), bank: owedTally(queue, "bank"), cash: owedTally(queue, "cash"), paidMonth: tally(paidMonth),
      }))
      .catch((err) => setError(err.message));
  }, []);

  const loadLists = useCallback(() => {
    Promise.all([
      api.get<Paginated<Voucher>>("/vouchers", { status: "approved", kind, page, per_page: 20 }),
      api.get<Paginated<Voucher>>("/vouchers", { status: "paid", kind, per_page: 10 }),
    ])
      .then(([queue, settled]) => { setDue(queue); setPaid(settled); })
      .catch((err) => setError(err.message));
  }, [kind, page]);

  useEffect(loadFigures, [loadFigures]);
  useEffect(loadLists, [loadLists]);

  const retry = () => { setError(null); loadFigures(); loadLists(); };

  if (error) return <ErrorState message={error} onRetry={retry} />;
  if (!due || !figures) return <LoadingBlock rows={5} />;

  const currency = company?.currency;
  const plural = (n: number) => (n === 1 ? t("voucherWord") : t("vouchersWord"));
  const shownTotal = due.meta?.total ?? due.data.length;
  const paidTotal = paid?.meta?.total ?? paid?.data.length ?? 0;

  return (
    <div className="app-page">
      <PageHeader
        title={`${figures.due.count} ${plural(figures.due.count)} ${t("awaitingPayment").toLowerCase()}`}
        sub={t("payNote")}
        actions={<>
          {/* Exports the report behind this screen, with the same bank/cash choice. */}
          <ExportMenu kind={filter === "cash" ? "cash" : "payments"} params={{ kind: filter === "bank" ? "bank" : "" }} />
          <Link className="btn btn-secondary" href="/vouchers"><Icon name="ph-receipt" size={15} /> {t("voucherRegister")}</Link>
        </>}
      />

      <div className="app-section">
        <FigureStrip>
          <Figure label={t("awaitingPayment")} value={money(figures.due.amount, currency)} sub={`${figures.due.count} ${plural(figures.due.count)}`} tone={figures.due.count ? "info" : undefined} />
          <Figure label={t("bankTransfers")} value={money(figures.bank.amount, currency)} sub={kindCount(figures.bank.count, "bank")} />
          <Figure label={t("cashDue")} value={money(figures.cash.amount, currency)} sub={kindCount(figures.cash.count, "cash")} />
          <Figure label={t("paidThisMonth")} value={money(figures.paidMonth.amount, currency)} sub={`${figures.paidMonth.count} ${plural(figures.paidMonth.count)}`} tone="ok" />
        </FigureStrip>
      </div>

      <div className="app-stack">
        <section className="vf-panel" aria-labelledby="due-title">
          <div className="vf-panel-head">
            <div className="vf-panel-head-main app-panel-title">
              <h2 id="due-title">{t("awaitingPayment")}</h2>
              <span className="vf-count">{shownTotal}</span>
            </div>
            <div className="seg seg-sm" role="tablist" aria-label={t("voucherFormat")}>
              {([["all", t("all")], ["bank", t("bank")], ["cash", t("cash")]] as const).map(([key, label]) => (
                <button key={key} type="button" role="tab" aria-selected={filter === key}
                  onClick={() => { setFilter(key); setPage(1); }}>{label}</button>
              ))}
            </div>
          </div>
          {due.data.length > 0 ? (
            <>
              <VoucherList vouchers={due.data} bare owing />
              <Pagination
                page={due.meta?.current_page ?? 1}
                lastPage={due.meta?.last_page ?? 1}
                total={shownTotal}
                onChange={setPage}
              />
              <div className="app-panel-foot"><Icon name="ph-info" size={15} /><span>{t("approveNextNote")}</span></div>
            </>
          ) : (
            <EmptyState tone="ok" icon="ph-check-circle" title={t("nothingAwaiting")} body={t("nothingAwaitingBody")}
              action={<Link className="btn btn-secondary" href="/vouchers">{t("voucherRegister")}</Link>} />
          )}
        </section>

        {paid && paid.data.length > 0 && (
          <section className="vf-panel" aria-labelledby="history-title">
            <div className="vf-panel-head">
              <div className="vf-panel-head-main app-panel-title"><h2 id="history-title">{t("paidVouchers")}</h2><span className="vf-count">{paidTotal}</span></div>
              <Link className="btn btn-ghost btn-sm" href="/vouchers?status=paid">{t("viewAllPaid")} <Icon name="ph-arrow-right" size={13} /></Link>
            </div>
            <VoucherTable vouchers={paid.data} bare />
          </section>
        )}
      </div>
    </div>
  );
}

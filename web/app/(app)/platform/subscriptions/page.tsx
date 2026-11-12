"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate, money } from "@/lib/format";
import { SUBSCRIPTION_STATUS, daysUntil, fill } from "@/lib/platform";
import { Badge, Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination, Spinner, StatPills } from "@/components/ui";
import { Dropdown, MenuItem, MenuSeparator, SearchInput, Toolbar } from "@/components/app-ui";
import type { Invoice, Paginated, Plan, Subscription } from "@/lib/types";

/*
 * Every subscription on the platform, running ones first by the date they
 * end. From each row the operator changes the plan, gives more time,
 * cancels (at the end of the period or now), reactivates, raises an
 * invoice, marks one paid after a bank transfer, or refunds the last one.
 */

interface ListResponse extends Paginated<Subscription> {
  unpaid_invoices: Record<string, Invoice> | [];
  paid_invoices: Record<string, Invoice> | [];
  summary: { running: number; trialing: number; active: number; past_due: number; ending: number; expiring_30: number };
}

type Action =
  | { kind: "extend" | "cancel" | "reactivate" | "plan" | "invoice"; sub: Subscription }
  | { kind: "paid" | "refund"; sub: Subscription; invoice: Invoice };

const RUNNING = ["trialing", "active", "past_due"];

export default function PlatformSubscriptionsPage() {
  const { t, locale, toast, reportError } = useApp();
  const [filters, setFilters] = useState({ q: "", status: "", plan_id: "", expiring: "" });
  const [page, setPage] = useState(1);
  const [result, setResult] = useState<ListResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [plans, setPlans] = useState<Plan[]>([]);
  const [action, setAction] = useState<Action | null>(null);
  const [busy, setBusy] = useState(false);
  // The inputs of the open dialog.
  const [days, setDays] = useState("30");
  const [until, setUntil] = useState("");
  const [when, setWhen] = useState<"period_end" | "immediately">("period_end");
  const [planId, setPlanId] = useState("");
  const [cycle, setCycle] = useState<"monthly" | "annual">("monthly");
  const [note, setNote] = useState("");

  // A link from the overview may carry ?expiring=30 or ?status=…
  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    const expiring = q.get("expiring") ?? "";
    const status = q.get("status") ?? "";
    // Read once from the address bar, an external source, after hydration.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (expiring || status) setFilters((f) => ({ ...f, expiring, status }));
  }, []);

  const load = useCallback(() => {
    setError(null);
    api.get<ListResponse>("/platform/subscriptions", { ...filters, page, per_page: 25 })
      .then(setResult).catch((err) => setError(err.message));
  }, [filters, page]);

  useEffect(() => {
    const timer = window.setTimeout(load, filters.q ? 260 : 0);
    return () => window.clearTimeout(timer);
  }, [load, filters.q]);

  useEffect(() => {
    api.get<{ data: Plan[] }>("/platform/plans").then((r) => setPlans(r.data)).catch(() => setPlans([]));
  }, []);

  const filter = (key: keyof typeof filters) => (value: string) => { setPage(1); setFilters((f) => ({ ...f, [key]: value })); };

  function open(next: Action) {
    setDays("30"); setUntil(""); setWhen("period_end"); setNote("");
    setPlanId(String(next.sub.plan?.id ?? "")); setCycle(next.sub.billing_cycle);
    setAction(next);
  }

  async function run() {
    if (!action) return;
    const s = action.sub;
    setBusy(true);
    try {
      switch (action.kind) {
        case "extend":
          await api.post(`/platform/subscriptions/${s.id}/extend`, until ? { until } : { days: Number(days) });
          toast(t("pfExtended"), s.company ?? "", "ok");
          break;
        case "cancel":
          await api.post(`/platform/subscriptions/${s.id}/cancel`, { when });
          toast(when === "immediately" ? t("pfCancelledNow") : t("pfCancelScheduled"), s.company ?? "", "warn");
          break;
        case "reactivate":
          await api.post(`/platform/subscriptions/${s.id}/reactivate`);
          toast(t("pfReactivated"), s.company ?? "", "ok");
          break;
        case "plan":
          await api.post(`/platform/companies/${s.company_id}/change-plan`, { plan_id: Number(planId), billing_cycle: cycle });
          toast(t("pfPlanChanged"), s.company ?? "", "ok");
          break;
        case "invoice":
          await api.post(`/platform/subscriptions/${s.id}/invoice`);
          toast(t("pfInvoiceIssued"), s.company ?? "", "ok");
          break;
        case "paid":
          await api.post(`/platform/payments/${action.invoice.id}/mark-paid`, { reference: note || undefined });
          toast(t("pfMarkedPaid"), action.invoice.number, "ok");
          break;
        case "refund":
          await api.post(`/platform/payments/${action.invoice.id}/refund`, { reason: note || undefined });
          toast(t("pfRefunded"), action.invoice.number, "warn");
          break;
      }
      setAction(null);
      load();
    } catch (err) {
      reportError(err, t("pfActionFailed"));
    } finally { setBusy(false); }
  }

  const rows = result?.data ?? [];
  const unpaid = (id: number) => (result?.unpaid_invoices as Record<string, Invoice> | undefined)?.[id];
  const paid = (id: number) => (result?.paid_invoices as Record<string, Invoice> | undefined)?.[id];
  const sum = result?.summary;
  const a = action;

  const dialogTitle: Record<Action["kind"], string> = {
    extend: t("pfExtendTitle"), cancel: t("pfCancelTitle"), reactivate: t("pfReactivateTitle"), plan: t("changePlan"),
    invoice: t("pfIssueInvoice"), paid: t("pfMarkPaid"), refund: t("pfRefund"),
  };
  const dialogSub: Record<Action["kind"], string> = {
    extend: t("pfExtendSub"), cancel: t("pfCancelSub"), reactivate: t("pfReactivateSub"), plan: t("pfChangePlanSub"),
    invoice: t("pfIssueInvoiceSub"), paid: t("pfMarkPaidSub"), refund: t("pfRefundSub"),
  };
  const danger = a?.kind === "refund" || (a?.kind === "cancel" && when === "immediately");

  return (
    <div className="app-page pf-page">
      <PageHeader kicker={t("pfPlatform")} title={t("pfSubscriptions")} subtitle={t("pfSubscriptionsSub")} />

      {sum && (
        <StatPills label={t("pfKeyFigures")} items={[
          { label: t("pfRunning"), value: sum.running, hint: fill(t("pfRunningHint"), { active: sum.active, trial: sum.trialing }), icon: "ph-arrows-clockwise", tone: "ok" },
          { label: t("pfStatusPastDue"), value: sum.past_due, icon: "ph-warning-circle", tone: sum.past_due ? "warn" : "neutral" },
          { label: t("pfEndingSoon"), value: sum.expiring_30, hint: t("pfNext30Days"), icon: "ph-calendar-x", tone: sum.expiring_30 ? "info" : "neutral" },
          { label: t("pfSetToEnd"), value: sum.ending, hint: t("pfSetToEndHint"), icon: "ph-hourglass-low", tone: sum.ending ? "warn" : "neutral" },
        ]} />
      )}

      <section className="vf-panel">
        <Toolbar end={result?.meta && <span className="pf-muted pf-nowrap">{fill(t("pfResults"), { n: result.meta.total })}</span>}>
          <SearchInput value={filters.q} onChange={filter("q")} placeholder={t("pfSearchCompany")} />
          <select className="input" value={filters.status} onChange={(e) => filter("status")(e.target.value)} aria-label={t("status")}>
            <option value="">{t("allStatuses")}</option>
            <option value="trialing">{t("pfStatusTrial")}</option>
            <option value="active">{t("pfStatusActive")}</option>
            <option value="past_due">{t("pfStatusPastDue")}</option>
            <option value="ending">{t("pfEndsAtPeriodEnd")}</option>
            <option value="cancelled">{t("pfStatusCancelled")}</option>
            <option value="expired">{t("pfStatusExpired")}</option>
          </select>
          <select className="input" value={filters.plan_id} onChange={(e) => filter("plan_id")(e.target.value)} aria-label={t("plan")}>
            <option value="">{t("pfAllPlans")}</option>
            {plans.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
          <select className="input" value={filters.expiring} onChange={(e) => filter("expiring")(e.target.value)} aria-label={t("pfRenewal")}>
            <option value="">{t("pfAnyRenewal")}</option>
            <option value="7">{fill(t("pfEndsWithin"), { n: 7 })}</option>
            <option value="30">{fill(t("pfEndsWithin"), { n: 30 })}</option>
            <option value="90">{fill(t("pfEndsWithin"), { n: 90 })}</option>
          </select>
        </Toolbar>

        {error && <div className="vf-panel-pad"><ErrorState message={error} onRetry={load} /></div>}
        {!result && !error && <div className="vf-panel-pad"><LoadingBlock rows={6} /></div>}
        {result && rows.length === 0 && <EmptyState icon="ph-arrows-clockwise" title={t("pfNoSubscriptions")} body={t("pfNoSubscriptionsBody")} />}

        {rows.length > 0 && (
          <>
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead>
                  <tr>
                    <th>{t("companyName")}</th><th>{t("plan")}</th><th>{t("status")}</th><th>{t("pfPeriod")}</th>
                    <th>{t("pfNextRenewal")}</th><th className="num">{t("pfAmount")}</th><th>{t("pfInvoice")}</th>
                    <th><span className="sr-only">{t("actions")}</span></th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((s) => {
                    const st = SUBSCRIPTION_STATUS[s.status];
                    const running = RUNNING.includes(s.status);
                    const left = daysUntil(s.current_period_end);
                    const due = unpaid(s.id);
                    const last = paid(s.id);
                    return (
                      <tr key={s.id}>
                        <td>
                          <Link className="pf-link" href={`/platform/companies/${s.company_id}#subscription`}>{s.company ?? `#${s.company_id}`}</Link>
                          <span className="pf-cell-sub">{fill(t("pfSince"), { date: formatDate(s.starts_at, locale) })}</span>
                        </td>
                        <td>{s.plan?.name ?? "-"}<span className="pf-cell-sub">{s.billing_cycle === "annual" ? t("pfYearly") : t("pfMonthly")}</span></td>
                        <td>
                          <Badge tone={st?.tone ?? "neutral"} dot>{st ? t(st.label) : s.status}</Badge>
                          {running && s.cancel_at_period_end && <span className="pf-cell-sub">{t("pfEndsAtPeriodEnd")}</span>}
                        </td>
                        <td className="pf-nowrap">{formatDate(s.current_period_start, locale)} → {formatDate(s.current_period_end, locale)}</td>
                        <td className="pf-nowrap">
                          {running && !s.cancel_at_period_end ? (
                            <>{formatDate(s.current_period_end, locale)}
                              {left !== null && <span className="pf-cell-sub pf-days" data-tone={left <= 3 ? "bad" : left <= 7 ? "warn" : undefined}>
                                {left >= 0 ? fill(t("pfInDays"), { n: left }) : fill(t("pfDaysAgo"), { n: -left })}
                              </span>}
                            </>
                          ) : <span className="pf-muted">{t("pfNoRenewal")}</span>}
                        </td>
                        <td className="num pf-nowrap">{money(s.amount, s.currency)}</td>
                        <td>
                          {due ? <Badge tone={due.status === "failed" ? "bad" : "warn"} dot>{due.number}</Badge>
                            : last ? <span className="pf-muted pf-nowrap">{last.number}</span> : <span className="pf-muted">-</span>}
                        </td>
                        <td className="app-row-actions">
                          <Dropdown floating label={fill(t("pfActionsFor"), { name: s.company ?? "" })}
                            trigger={({ open: isOpen, toggle, id }) => (
                              <button type="button" className="btn btn-icon btn-sm" onClick={toggle} aria-expanded={isOpen} aria-controls={id}
                                aria-haspopup="menu" aria-label={fill(t("pfActionsFor"), { name: s.company ?? "" })}>
                                <Icon name="ph-dots-three-outline" size={18} />
                              </button>
                            )}>
                            {(close) => (
                              <>
                                <MenuItem icon="ph-crown-simple" onSelect={() => { close(); open({ kind: "plan", sub: s }); }}>{t("changePlan")}</MenuItem>
                                {running && <MenuItem icon="ph-calendar-plus" onSelect={() => { close(); open({ kind: "extend", sub: s }); }}>{t("pfExtend")}</MenuItem>}
                                {(!running || s.cancel_at_period_end) && (
                                  <MenuItem icon="ph-arrow-counter-clockwise" onSelect={() => { close(); open({ kind: "reactivate", sub: s }); }}>{t("pfReactivate")}</MenuItem>
                                )}
                                <MenuSeparator />
                                {due
                                  ? <MenuItem icon="ph-check-circle" onSelect={() => { close(); open({ kind: "paid", sub: s, invoice: due }); }}>{fill(t("pfMarkPaidN"), { n: due.number })}</MenuItem>
                                  : running && <MenuItem icon="ph-file-plus" onSelect={() => { close(); open({ kind: "invoice", sub: s }); }}>{t("pfIssueInvoice")}</MenuItem>}
                                {last && <MenuItem icon="ph-arrow-u-up-left" onSelect={() => { close(); open({ kind: "refund", sub: s, invoice: last }); }}>{fill(t("pfRefundN"), { n: last.number })}</MenuItem>}
                                {running && (
                                  <>
                                    <MenuSeparator />
                                    <MenuItem icon="ph-prohibit" tone="danger" onSelect={() => { close(); open({ kind: "cancel", sub: s }); }}>{t("pfCancelSubscription")}</MenuItem>
                                  </>
                                )}
                              </>
                            )}
                          </Dropdown>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <Pagination page={result?.meta?.current_page ?? 1} lastPage={result?.meta?.last_page ?? 1}
              total={result?.meta?.total ?? rows.length} onChange={setPage} />
          </>
        )}
      </section>

      <Dialog open={a !== null} busy={busy} onClose={() => setAction(null)}
        icon={a?.kind === "cancel" ? "ph-prohibit" : a?.kind === "refund" ? "ph-arrow-u-up-left" : a?.kind === "extend" ? "ph-calendar-plus" : "ph-arrows-clockwise"}
        tone={danger ? "bad" : a?.kind === "cancel" ? "warn" : "info"}
        title={a ? dialogTitle[a.kind] : ""} sub={a ? dialogSub[a.kind] : undefined}
        summary={a ? [
          { label: t("companyName"), value: a.sub.company ?? "-" },
          { label: t("plan"), value: a.sub.plan?.name ?? "-" },
          ...(a.kind === "paid" || a.kind === "refund"
            ? [{ label: t("pfInvoice"), value: `${a.invoice.number} · ${a.invoice.amount_text}` }]
            : [{ label: t("pfEnds"), value: formatDate(a.sub.current_period_end, locale) }]),
        ] : undefined}
        actions={<>
          <button type="button" className="btn btn-secondary" onClick={() => setAction(null)} disabled={busy}>{t("cancel")}</button>
          <button type="button" className={danger ? "btn btn-danger-solid" : "btn btn-primary"} onClick={() => void run()}
            disabled={busy || (a?.kind === "plan" && !planId) || (a?.kind === "extend" && !until && !(Number(days) > 0))}>
            {busy ? <Spinner /> : t("confirm")}
          </button>
        </>}>
        {a?.kind === "extend" && (
          <div className="pf-form-row">
            <Field label={t("pfAddDays")} htmlFor="sx-days">
              <input id="sx-days" className="input tnum" type="number" min={1} max={730} value={days} disabled={!!until}
                onChange={(e) => setDays(e.target.value)} />
            </Field>
            <Field label={t("pfOrUntil")} htmlFor="sx-until" hint={t("pfOrUntilHint")}>
              <input id="sx-until" className="input" type="date" value={until} onChange={(e) => setUntil(e.target.value)} />
            </Field>
          </div>
        )}
        {a?.kind === "cancel" && (
          <div className="pf-checks" role="radiogroup" aria-label={t("pfCancelWhen")}>
            <label className="pf-check">
              <input type="radio" name="cancel-when" checked={when === "period_end"} onChange={() => setWhen("period_end")} />
              <span>{t("pfAtPeriodEnd")}<small>{fill(t("pfAtPeriodEndHint"), { date: formatDate(a.sub.current_period_end, locale) })}</small></span>
            </label>
            <label className="pf-check">
              <input type="radio" name="cancel-when" checked={when === "immediately"} onChange={() => setWhen("immediately")} />
              <span>{t("pfImmediately")}<small>{t("pfImmediatelyHint")}</small></span>
            </label>
          </div>
        )}
        {a?.kind === "plan" && (
          <div className="pf-form-row">
            <Field label={t("plan")} htmlFor="sx-plan">
              <select id="sx-plan" className="input" value={planId} onChange={(e) => setPlanId(e.target.value)}>
                {plans.filter((p) => p.is_active || String(p.id) === planId).map((p) => (
                  <option key={p.id} value={p.id}>{p.name} · {p.price > 0 ? money(p.price, p.currency) : t("pfCustomPrice")}</option>
                ))}
              </select>
            </Field>
            <Field label={t("pfBillingCycle")} htmlFor="sx-cycle">
              <select id="sx-cycle" className="input" value={cycle} onChange={(e) => setCycle(e.target.value as "monthly" | "annual")}>
                <option value="monthly">{t("pfMonthly")}</option>
                <option value="annual">{t("pfYearly")}</option>
              </select>
            </Field>
          </div>
        )}
        {a?.kind === "paid" && (
          <Field label={t("pfPaymentReference")} htmlFor="sx-ref" hint={t("pfPaymentReferenceHint")}>
            <input id="sx-ref" className="input" value={note} maxLength={60} onChange={(e) => setNote(e.target.value)} />
          </Field>
        )}
        {a?.kind === "refund" && (
          <Field label={t("pfRefundReason")} htmlFor="sx-reason">
            <input id="sx-reason" className="input" value={note} maxLength={255} onChange={(e) => setNote(e.target.value)} />
          </Field>
        )}
      </Dialog>
    </div>
  );
}

"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate, money } from "@/lib/format";
import { Dialog, EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Spinner } from "@/components/ui";
import { Figure, FigureStrip, SearchInput } from "@/components/app-ui";
import { VoucherList, VoucherRow } from "@/components/voucher-bits";
import type { Voucher } from "@/lib/types";

type Kind = "all" | "bank" | "cash";

/** Whether this row can be approved from the list: an approving step that is ready, or one the saved signature can sign. */
function bulkEligible(v: Voucher): boolean {
  return Boolean(v.actions?.approve || (v.actions?.sign && v.current_step?.capabilities?.approve));
}

/**
 * Every voucher waiting on this person's step, laid out for deciding.
 *
 * Each row answers what is being asked, by whom, for how much, from which
 * department, and how far along the route it is — and leads to the voucher,
 * where the decision itself is taken behind a confirmation.
 */
export default function ApprovalsPage() {
  const { t, locale, company, toast, reportError, refreshUnread } = useApp();
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [confirming, setConfirming] = useState(false);
  const [reviewed, setReviewed] = useState(false);
  const [comment, setComment] = useState("");
  const [busy, setBusy] = useState(false);
  const [queue, setQueue] = useState<Voucher[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [q, setQ] = useState("");
  const [kind, setKind] = useState<Kind>("all");

  const load = useCallback(() => {
    setError(null);
    api.get<{ data: Voucher[] }>("/vouchers/pending")
      .then((r) => setQueue(r.data))
      .catch((err) => setError(err.message));
  }, []);

  useEffect(load, [load, locale]);

  const shown = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return (queue ?? []).filter((v) => (kind === "all" || v.kind === kind)
      && (!needle || [v.number, v.purpose, v.payee, v.requester?.name, v.department?.name].some((x) => x?.toLowerCase().includes(needle))));
  }, [queue, q, kind]);

  const eligible = shown.filter(bulkEligible);
  const chosen = (queue ?? []).filter((v) => selected.has(v.id));
  const chosenTotal = chosen.reduce((sum, v) => sum + v.amount, 0);
  const toggle = (id: number) => setSelected((prev) => { const next = new Set(prev); if (next.has(id)) next.delete(id); else next.add(id); return next; });
  const allChosen = eligible.length > 0 && eligible.every((v) => selected.has(v.id));

  async function bulkApprove() {
    setBusy(true);
    try {
      const r = await api.post<{ approved: { id: number; number: string }[]; skipped: { id: number; number: string | null; reason: string }[] }>(
        "/vouchers/bulk-approve", { ids: chosen.map((v) => v.id), comment: comment.trim() || null, confirm: true });
      const skippedText = r.skipped.map((x) => `${x.number ?? `#${x.id}`}: ${x.reason}`).join(" ");
      toast(
        locale === "sw" ? `Vocha ${r.approved.length} zimeidhinishwa` : `${r.approved.length} ${r.approved.length === 1 ? "voucher" : "vouchers"} approved`,
        r.skipped.length ? `${locale === "sw" ? "Zilizorukwa" : "Skipped"} — ${skippedText}` : undefined,
        r.skipped.length ? "warn" : "ok",
      );
      setSelected(new Set()); setConfirming(false); setReviewed(false); setComment("");
      load(); refreshUnread?.();
    } catch (err) {
      reportError(err, locale === "sw" ? "Imeshindikana kuidhinisha" : "Could not approve");
    } finally {
      setBusy(false);
    }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!queue) return <LoadingBlock rows={4} />;

  const sw = locale === "sw";
  const total = queue.reduce((sum, v) => sum + v.amount, 0);
  const oldest = [...queue].sort((a, b) => String(a.submitted_at ?? a.voucher_date).localeCompare(String(b.submitted_at ?? b.voucher_date)))[0];

  return (
    <div className="app-page">
      <PageHeader
        title={queue.length > 0 ? `${queue.length} ${queue.length === 1 ? t("voucherWord") : t("vouchersWord")} ${t("awaitingYou")}` : t("nothingAwaiting")}
        sub={queue.length > 0 && queue.every((v) => !v.current_step?.capabilities?.approve) ? t("signOnlyNote") : t("bulkApproveIntro")}
        actions={<Link className="btn btn-secondary" href="/vouchers"><Icon name="ph-receipt" size={15} /> {t("voucherRegister")}</Link>}
      />

      {queue.length > 0 && (
        <div className="app-section">
          <FigureStrip>
            <Figure label={t("awaitingYouLabel")} value={queue.length} tone="info" />
            <Figure label={t("total")} value={money(total, company?.currency)} />
            <Figure label={t("bank")} value={queue.filter((v) => v.kind === "bank").length} />
            <Figure label={t("cash")} value={queue.filter((v) => v.kind === "cash").length} />
            {oldest && <Figure label={sw ? "Inasubiri tangu" : "Waiting since"} value={formatDate(oldest.submitted_at ?? oldest.voucher_date, locale)} sub={oldest.number} />}
          </FigureStrip>
        </div>
      )}

      <section className="vf-panel">
        {queue.length > 0 && (
          <div className="app-toolbar">
            <div className="app-toolbar-main">
              <SearchInput value={q} onChange={setQ} placeholder={t("searchPh")} />
              <div className="seg seg-sm" role="tablist" aria-label={t("voucherFormat")}>
                {([["all", t("all")], ["bank", t("bank")], ["cash", t("cash")]] as const).map(([key, label]) => (
                  <button key={key} type="button" role="tab" aria-selected={kind === key} onClick={() => setKind(key)}>{label}</button>
                ))}
              </div>
            </div>
            <div className="app-toolbar-end">
              {eligible.length > 1 && (
                <label className="app-bulk-all">
                  <input type="checkbox" checked={allChosen}
                    onChange={() => setSelected(allChosen ? new Set() : new Set(eligible.map((v) => v.id)))} />
                  {t("selectAllForApproval")}
                </label>
              )}
              <span className="app-result-count">{t("showing")} {shown.length} {t("of")} {queue.length}</span>
            </div>
          </div>
        )}

        {queue.length === 0 ? (
          <EmptyState tone="ok" icon="ph-check-circle" title={t("nothingAwaiting")} body={t("nothingAwaitingBody")}
            action={<Link className="btn btn-secondary" href="/vouchers"><Icon name="ph-receipt" size={15} /> {t("register")}</Link>} />
        ) : shown.length === 0 ? (
          <EmptyState icon="ph-magnifying-glass" title={t("noResults")} />
        ) : (
          <>
            {eligible.length > 0 ? (
              <div className="vf-list">
                {shown.map((v) => (
                  <div key={v.id} className="app-bulk-row" data-selected={selected.has(v.id) || undefined}>
                    {bulkEligible(v)
                      ? <input type="checkbox" aria-label={`${t("select")} ${v.number}`} checked={selected.has(v.id)} onChange={() => toggle(v.id)} />
                      : <span className="app-bulk-spacer" aria-hidden="true" />}
                    <div className="app-bulk-main"><VoucherRow voucher={v} /></div>
                  </div>
                ))}
              </div>
            ) : (
              <VoucherList vouchers={shown} bare />
            )}
            <div className="app-panel-foot"><Icon name="ph-shield-check" size={15} /><span>{t("clearedNote")}</span></div>
          </>
        )}
      </section>
      {chosen.length > 0 && (
        <div className="app-bulk-bar" role="region" aria-label={t("bulkApprove")}>
          <span><strong className="tnum">{chosen.length}</strong> {t("selected")} · <span className="tnum">{money(chosenTotal, company?.currency)}</span></span>
          <div className="app-bulk-bar-actions">
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setSelected(new Set())}>{t("clearSelection")}</button>
            <button type="button" className="btn btn-primary btn-sm" onClick={() => setConfirming(true)}>
              <Icon name="ph-seal-check" size={15} /> {t("approveSelected")} ({chosen.length})
            </button>
          </div>
        </div>
      )}

      <Dialog
        open={confirming}
        onClose={() => !busy && setConfirming(false)}
        icon="ph-seal-check" tone="ok"
        title={locale === "sw" ? `Idhinisha vocha ${chosen.length}?` : `Approve ${chosen.length} ${chosen.length === 1 ? "voucher" : "vouchers"}?`}
        sub={t("bulkApproveSub")}
        summary={[
          { label: t("bulkCount"), value: chosen.length },
          { label: t("total"), value: money(chosenTotal, company?.currency) },
        ]}
        busy={busy}
        actions={(
          <>
            <button type="button" className="btn btn-ghost" onClick={() => setConfirming(false)} disabled={busy}>{t("cancel")}</button>
            <button type="button" className="btn btn-primary" onClick={() => void bulkApprove()} disabled={!reviewed || busy}>
              {busy ? <Spinner /> : <><Icon name="ph-seal-check" size={16} /> {t("approveSelected")}</>}
            </button>
          </>
        )}
      >
        <ul className="app-bulk-list">
          {chosen.map((v) => (
            <li key={v.id}><span className="tnum">{v.number}</span><span className="app-bulk-list-purpose">{v.purpose}</span><span className="tnum">{v.amount_text}</span></li>
          ))}
        </ul>
        <div className="field" style={{ marginTop: 12 }}>
          <label className="field-label" htmlFor="bulk-comment">{t("bulkComment")}</label>
          <textarea id="bulk-comment" className="input" rows={2} value={comment} onChange={(e) => setComment(e.target.value)} />
        </div>
        <label className="app-bulk-statement">
          <input type="checkbox" checked={reviewed} onChange={(e) => setReviewed(e.target.checked)} />
          <span>{t("bulkReviewedStatement")}</span>
        </label>
      </Dialog>
    </div>
  );
}

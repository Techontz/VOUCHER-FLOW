"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import type { CashbookEntry } from "@/lib/finance-api";
import { formatDate, formatDateTime } from "@/lib/format";
import { Dialog, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { DocStatus, ErpGate } from "@/components/erp-ui";
import { DetailRows, FinanceTabs, JournalLines } from "@/components/finance-ui";
import { CashbookDialog } from "@/components/finance-cashbook-form";

export default function CashbookEntryPage() {
  return <ErpGate module="accounting" permission="finance.view"><Entry /></ErpGate>;
}

function Entry() {
  const { t, locale, toast } = useApp();
  const { can, config } = useErp();
  const { id } = useParams<{ id: string }>();
  const [entry, setEntry] = useState<CashbookEntry | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [confirm, setConfirm] = useState<"post" | "reverse" | "cancel" | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const load = useCallback(() => {
    api.get<{ data: CashbookEntry }>(`/erp/finance/cashbook/${id}`).then((r) => setEntry(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  async function act() {
    if (!entry || !confirm) return;
    setBusy(true); setActionError(null);
    try {
      const r = await api.post<{ message: string }>(`/erp/finance/cashbook/${entry.id}/${confirm}`, confirm === "reverse" ? { reason } : undefined);
      toast(r.message, undefined, "ok");
      setConfirm(null); setReason(""); load();
    } catch (e) { setActionError(e instanceof ApiError ? e.message : String(e)); } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!entry) return <LoadingBlock rows={6} />;

  const may = can("finance.cashbook");
  const draft = entry.status === "draft";
  const receipt = entry.type === "receipt";

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/finance/cashbook" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("finTabCashbook")}</Link>}
        kicker={t(receipt ? "finReceipt" : "finPayment")}
        title={<span className="erp-inline-icon tnum"><Icon name={receipt ? "ph-arrow-down-left" : "ph-arrow-up-right"} size={30} /> {entry.number}</span>}
        subtitle={<>{entry.description} · {formatDate(entry.entry_date, locale)}</>}
        actions={<>
          <DocStatus status={entry.status} />
          {draft && may && <button className="btn btn-secondary" onClick={() => setEditing(true)}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</button>}
          {draft && may && <button className="btn btn-secondary" onClick={() => { setActionError(null); setConfirm("cancel"); }}>{t("erpCancelDraft")}</button>}
          {draft && may && <button className="btn btn-primary" onClick={() => { setActionError(null); setConfirm("post"); }}><Icon name="ph-check-circle" size={18} /> {t("erpPost")}</button>}
          {entry.status === "posted" && may && <button className="btn btn-secondary" onClick={() => { setActionError(null); setConfirm("reverse"); }}><Icon name="ph-arrow-u-up-left" size={17} /> {t("erpReverse")}</button>}
        </>}
      />
      <FinanceTabs />

      <div className="erp-grid">
        <GlassCard title={t("finDetails")} pad={false}>
          <DetailRows rows={[
            { label: t("finAmount"), value: <strong className="tnum">{config?.settings.base_currency ?? "TZS"} {amount(entry.amount)}</strong> },
            { label: t(receipt ? "finIntoAccount" : "finFromAccount"), value: entry.bank_account?.name },
            { label: t(receipt ? "finIncomeAccount" : "finExpenseAccount"), value: <><span className="tnum">{entry.account?.code}</span> {entry.account?.name}</> },
            { label: t(receipt ? "finReceivedFrom" : "finPaidTo"), value: entry.counterparty ?? "-" },
            { label: t("erpReference"), value: entry.reference ?? "-" },
          ]} />
        </GlassCard>
        <GlassCard title={t("finTimeline")}>
          <ul className="erp-list">
            <li className="erp-list-row"><span className="erp-list-main"><span className="erp-list-title">{t("erpPrepared")}</span><span className="erp-list-sub">{entry.creator?.name} · {formatDateTime(entry.created_at, locale)}</span></span></li>
            {entry.posted_at && <li className="erp-list-row"><span className="erp-list-main"><span className="erp-list-title">{t("erpStatusPosted")}</span><span className="erp-list-sub">{entry.poster?.name} · {formatDateTime(entry.posted_at, locale)}</span></span></li>}
            {entry.reversed_at && <li className="erp-list-row"><span className="erp-list-main"><span className="erp-list-title">{t("erpStatusReversed")}</span><span className="erp-list-sub">{entry.reverser?.name} · {formatDateTime(entry.reversed_at, locale)} · {entry.reversal_reason}</span></span></li>}
          </ul>
        </GlassCard>
        {entry.journal?.lines && <GlassCard className="erp-span-2" title={t("finJournal")} pad={false}><JournalLines lines={entry.journal.lines} number={entry.journal.number} /></GlassCard>}
      </div>

      {editing && <CashbookDialog entry={entry} type={entry.type} onClose={() => setEditing(false)} onSaved={() => { setEditing(false); load(); }} />}
      <Dialog open={!!confirm} onClose={() => setConfirm(null)} busy={busy}
        icon={confirm === "post" ? "ph-check-circle" : "ph-arrow-u-up-left"} tone={confirm === "post" ? "info" : "warn"}
        title={t(confirm === "post" ? "finPostEntryQ" : confirm === "reverse" ? "finReverseEntryQ" : "finCancelEntryQ")}
        summary={[{ label: t("finAmount"), value: amount(entry.amount) }, { label: t("finBankAccount"), value: entry.bank_account?.name }, { label: t("erpDate"), value: formatDate(entry.entry_date, locale) }]}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setConfirm(null)} disabled={busy}>{t("erpBack")}</button>
          <button className={confirm === "post" ? "btn btn-primary" : "btn btn-danger"} onClick={act} disabled={busy || (confirm === "reverse" && reason.trim().length < 3)}>
            {t(confirm === "post" ? "erpPost" : confirm === "reverse" ? "erpReverse" : "erpCancelDraft")}
          </button>
        </>}>
        {confirm === "reverse" && <Field label={t("erpReason")} htmlFor="ce-reason" required><input id="ce-reason" className="input" value={reason} onChange={(e) => setReason(e.target.value)} autoFocus /></Field>}
        {actionError && <div className="field-error" role="alert">{actionError}</div>}
      </Dialog>
    </div>
  );
}

"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import { type BankAccountDetail, monthStart, today } from "@/lib/finance-api";
import { formatDate } from "@/lib/format";
import { Badge, Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { Amount, BANK_TYPE_LABEL, FinanceTabs } from "@/components/finance-ui";
import { BankAccountDialog } from "@/components/finance-bank-form";

export default function BankPage() {
  return <ErpGate module="accounting" permission="finance.view"><Bank /></ErpGate>;
}

/** Where a ledger line came from, as a link when the source has a screen. */
function sourceHref(source: string | null, id: number | null): string | null {
  if (!source || !id) return null;
  return ({ CashbookEntry: `/erp/finance/cashbook/${id}`, FixedAsset: `/erp/assets/register/${id}`, StockDocument: `/erp/documents/${id}` } as Record<string, string>)[source] ?? null;
}

function Bank() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const { id } = useParams<{ id: string }>();
  const [from, setFrom] = useState(monthStart(-2));
  const [to, setTo] = useState(today());
  const [bank, setBank] = useState<BankAccountDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [closing, setClosing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const load = useCallback(() => {
    api.get<{ data: BankAccountDetail }>(`/erp/finance/bank-accounts/${id}`, { from, to }).then((r) => setBank(r.data)).catch((e) => setError(e.message));
  }, [id, from, to]);
  useEffect(load, [load]);

  async function setActive(active: boolean) {
    if (!bank) return;
    setBusy(true); setActionError(null);
    try {
      await api.put(`/erp/finance/bank-accounts/${bank.id}`, { is_active: active });
      toast(t("erpSaved"), bank.name, "ok");
      setClosing(false); load();
    } catch (e) { setActionError(e instanceof ApiError ? e.message : String(e)); } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!bank) return <LoadingBlock rows={6} />;

  const s = bank.statement;
  const inflow = s.lines.reduce((sum, l) => sum + Number(l.debit), 0);
  const outflow = s.lines.reduce((sum, l) => sum + Number(l.credit), 0);

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/finance/banks" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("finTabBanks")}</Link>}
        kicker={`${t(BANK_TYPE_LABEL[bank.type])} · ${bank.account?.code}`}
        title={bank.name}
        subtitle={[bank.bank_name, bank.branch, bank.account_number].filter(Boolean).join(" · ")}
        actions={<>
          {!bank.is_active && <Badge>{t("erpInactive")}</Badge>}
          {can("finance.bank") && <button className="btn btn-secondary" onClick={() => setEditing(true)}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</button>}
          {can("finance.bank") && (bank.is_active
            ? <button className="btn btn-secondary" onClick={() => { setActionError(null); setClosing(true); }}>{t("finCloseAccount")}</button>
            : <button className="btn btn-secondary" onClick={() => setActive(true)} disabled={busy}>{t("finReopenAccount")}</button>)}
          {can("finance.bank") && bank.is_active && <Link className="btn btn-primary" href={`/erp/finance/reconciliations?bank=${bank.id}`}><Icon name="ph-checks" size={17} /> {t("finReconcile")}</Link>}
        </>}
      />
      <FinanceTabs />

      <StatPills items={[
        { label: t("erpBalance"), value: amount(bank.balance), icon: "ph-wallet" },
        { label: t("finMoneyIn"), value: amount(inflow), icon: "ph-arrow-down-left", hint: t("finInRange") },
        { label: t("finMoneyOut"), value: amount(outflow), icon: "ph-arrow-up-right", hint: t("finInRange") },
        { label: t("finOpeningBalance"), value: amount(bank.opening_balance), icon: "ph-flag-banner", hint: bank.opening_date ? formatDate(bank.opening_date, locale) : undefined },
      ]} />

      <div className="fin-filters">
        <Field label={t("finFrom")} htmlFor="s-from"><input id="s-from" type="date" className="input" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label={t("finTo")} htmlFor="s-to"><input id="s-to" type="date" className="input" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
      </div>

      <GlassCard title={t("finAccountStatement")} subtitle={`${t("finOpening")}: ${amount(s.opening)} · ${t("finClosing")}: ${amount(s.closing)}`} pad={false}>
        {s.lines.length === 0 ? <EmptyState icon="ph-list" title={t("finNoMovements")} /> : (
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpDate")}</th><th>{t("erpReference")}</th><th>{t("finDescription")}</th><th className="num">{t("finMoneyIn")}</th><th className="num">{t("finMoneyOut")}</th><th className="num">{t("erpBalance")}</th><th /></tr></thead>
              <tbody>
                {s.lines.map((l) => {
                  const href = sourceHref(l.source_type, l.source_id);
                  return (
                    <tr key={l.id}>
                      <td className="tnum">{formatDate(l.entry_date, locale)}</td>
                      <td className="tnum">{href ? <Link href={href}>{l.number}</Link> : l.number}</td>
                      <td>{l.description || l.memo}</td>
                      <td className="num">{Number(l.debit) ? amount(l.debit) : ""}</td>
                      <td className="num">{Number(l.credit) ? amount(l.credit) : ""}</td>
                      <td className="num"><Amount value={l.balance} /></td>
                      <td>{l.reconciled && <Badge tone="ok">{t("finReconciled")}</Badge>}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </GlassCard>

      {bank.reconciliations.length > 0 && (
        <GlassCard title={t("finTabReconcile")} pad={false}>
          <ul className="erp-list">
            {bank.reconciliations.map((r) => (
              <li key={r.id}>
                <Link className="erp-list-row" href={`/erp/finance/reconciliations/${r.id}`}>
                  <span className="erp-list-main"><span className="erp-list-title tnum">{r.number}</span><span className="erp-list-sub">{formatDate(r.statement_date, locale)} · {amount(r.statement_closing_balance)}</span></span>
                  <Badge tone={r.status === "completed" ? "ok" : "info"} dot>{t(r.status === "completed" ? "finCompleted" : "finInProgress")}</Badge>
                </Link>
              </li>
            ))}
          </ul>
        </GlassCard>
      )}

      {editing && <BankAccountDialog bank={bank} onClose={() => setEditing(false)} onSaved={() => { setEditing(false); load(); }} />}
      <Dialog open={closing} title={t("finCloseAccount")} sub={t("finCloseAccountHint")} icon="ph-lock-simple" tone="warn" onClose={() => setClosing(false)} busy={busy}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setClosing(false)} disabled={busy}>{t("erpBack")}</button>
          <button className="btn btn-danger" onClick={() => setActive(false)} disabled={busy}>{t("finCloseAccount")}</button>
        </>}>
        {actionError && <div className="field-error" role="alert">{actionError}</div>}
      </Dialog>
    </div>
  );
}

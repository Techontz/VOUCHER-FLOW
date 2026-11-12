"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Account, type AccountType, amount, type JournalEntry, type Paginated, type TrialBalance, useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { Badge, Dialog, EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader, Pagination, StatPills } from "@/components/ui";
import { Tabs } from "@/components/app-ui";
import { ACCOUNT_TYPE_LABEL, ErpGate, fill } from "@/components/erp-ui";

type Tab = "chart" | "journals" | "trial";
const TYPES: AccountType[] = ["asset", "liability", "equity", "income", "expense"];

export default function AccountsPage() {
  return <ErpGate module="accounting" permission="accounting.view"><Accounts /></ErpGate>;
}

function Accounts() {
  const { t } = useApp();
  const { can } = useErp();
  const [tab, setTab] = useState<Tab>("chart");
  const [accounts, setAccounts] = useState<Account[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [journalOpen, setJournalOpen] = useState(false);
  const [version, setVersion] = useState(0);

  const load = useCallback(() => {
    api.get<{ data: Account[] }>("/erp/accounts").then((r) => setAccounts(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load, version]);

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!accounts) return <LoadingBlock rows={6} />;

  return (
    <div className="erp-page">
      <PageHeader title={t("erpAccounts")} subtitle={t("erpAccountsSub")}
        actions={can("accounting.post") && <button className="btn btn-primary" onClick={() => setJournalOpen(true)}><Icon name="ph-plus" size={18} /> {t("erpNewJournal")}</button>} />
      <Tabs label={t("erpAccounts")} value={tab} onChange={setTab} items={[
        { value: "chart", label: t("erpChart"), icon: "ph-tree-structure" },
        { value: "journals", label: t("erpJournals"), icon: "ph-notebook" },
        { value: "trial", label: t("erpTrialBalance"), icon: "ph-scales" },
      ]} />
      {tab === "chart" && <Chart accounts={accounts} onChange={() => setVersion((v) => v + 1)} />}
      {tab === "journals" && <Journals key={version} onChange={() => setVersion((v) => v + 1)} />}
      {tab === "trial" && <Trial key={version} />}
      {journalOpen && <JournalDialog accounts={accounts} onClose={() => setJournalOpen(false)} onPosted={() => { setJournalOpen(false); setVersion((v) => v + 1); setTab("journals"); }} />}
    </div>
  );
}

function Chart({ accounts, onChange }: { accounts: Account[]; onChange: () => void }) {
  const { t, toast } = useApp();
  const { can } = useErp();
  const [form, setForm] = useState<{ row: Account | null; code: string; name: string; type: AccountType; is_active: boolean } | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  async function save() {
    if (!form) return;
    setBusy(true); setFormError(null);
    try {
      const body = { code: form.code, name: form.name, type: form.type, is_active: form.is_active };
      if (form.row) await api.put(`/erp/accounts/${form.row.id}`, body); else await api.post("/erp/accounts", body);
      toast(t("erpSaved"), `${form.code} ${form.name}`, "ok");
      setForm(null); onChange();
    } catch (e) { setFormError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  return (
    <>
      <div className="erp-grid">
        {TYPES.map((type) => {
          const rows = accounts.filter((a) => a.type === type);
          return (
            <GlassCard key={type} title={t(ACCOUNT_TYPE_LABEL[type])} subtitle={String(rows.length)} pad={false}
              action={can("accounting.manage") ? <button className="btn btn-icon" aria-label={t("erpNewAccount")} onClick={() => { setFormError(null); setForm({ row: null, code: "", name: "", type, is_active: true }); }}><Icon name="ph-plus" size={17} /></button> : undefined}>
              <ul className="erp-list">
                {rows.map((a) => (
                  <li key={a.id}>
                    <button type="button" className="erp-list-row" disabled={!can("accounting.manage")}
                      onClick={() => { setFormError(null); setForm({ row: a, code: a.code, name: a.name, type: a.type, is_active: a.is_active }); }}>
                      <span className="erp-list-icon tnum">{a.code}</span>
                      <span className="erp-list-main">
                        <span className="erp-list-title">{a.name}</span>
                        {a.system_key && <span className="erp-list-sub">{t("erpSystemAccount")}</span>}
                      </span>
                      <span className="tnum">{amount(a.balance)}</span>
                      {!a.is_active && <Badge>{t("erpInactive")}</Badge>}
                    </button>
                  </li>
                ))}
              </ul>
            </GlassCard>
          );
        })}
      </div>

      {form && (
        <Dialog open title={form.row ? `${form.row.code} · ${form.row.name}` : t("erpNewAccount")} onClose={() => setForm(null)} busy={busy}
          actions={<>
            <button className="btn btn-secondary" onClick={() => setForm(null)} disabled={busy}>{t("erpCancel")}</button>
            <button className="btn btn-primary" onClick={save} disabled={busy || !form.code || !form.name}>{t("erpSave")}</button>
          </>}>
          {formError && !Object.keys(formError.errors).length && <div className="field-error" role="alert">{formError.message}</div>}
          <div className="erp-form-grid">
            <Field label={t("erpCode")} htmlFor="a-code" required error={formError?.field("code")}>
              <input id="a-code" className="input tnum" value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} />
            </Field>
            <Field label={t("erpName")} htmlFor="a-name" required error={formError?.field("name")}>
              <input id="a-name" className="input" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
            </Field>
            <Field label={t("erpType")} htmlFor="a-type">
              <select id="a-type" className="input" value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value as AccountType })}>
                {TYPES.map((x) => <option key={x} value={x}>{t(ACCOUNT_TYPE_LABEL[x])}</option>)}
              </select>
            </Field>
          </div>
        </Dialog>
      )}
    </>
  );
}

function Journals({ onChange }: { onChange: () => void }) {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<JournalEntry> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [reversing, setReversing] = useState<JournalEntry | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  useEffect(() => { api.get<Paginated<JournalEntry>>("/erp/journals", { page }).then(setRows).catch((e) => setError(e.message)); }, [page]);

  async function reverse() {
    if (!reversing) return;
    setBusy(true); setActionError(null);
    try {
      const r = await api.post<{ message: string }>(`/erp/journals/${reversing.id}/reverse`, { reason });
      toast(r.message, undefined, "ok");
      setReversing(null); setReason(""); onChange();
    } catch (e) { setActionError(e instanceof ApiError ? e.message : String(e)); } finally { setBusy(false); }
  }

  if (error) return <ErrorState message={error} />;
  if (!rows) return <LoadingBlock />;
  if (rows.data.length === 0) return <EmptyState icon="ph-notebook" title={t("erpNoJournals")} />;

  return (
    <>
      <div className="erp-journals">
        {rows.data.map((j) => (
          <GlassCard key={j.id}
            title={<span className="tnum">{j.number}</span>}
            subtitle={<>{formatDate(j.entry_date, locale)} · {j.memo}</>}
            action={<>
              {j.source_type === "StockDocument" && j.source_id && <Link className="vf-card-link" href={`/erp/documents/${j.source_id}`}>{t("erpSource")}</Link>}
              {!j.source_type && <Badge>{t("erpManual")}</Badge>}
              {j.status === "reversed" && <Badge tone="warn">{t("erpStatusReversed")}</Badge>}
              {j.reversal_of_id && <Badge tone="info">{t("erpReversalOf")}</Badge>}
              {j.status === "posted" && !j.reversal_of_id && can("accounting.reverse") && (
                <button className="btn btn-secondary btn-sm" onClick={() => { setActionError(null); setReversing(j); }}><Icon name="ph-arrow-u-up-left" size={15} /> {t("erpReverse")}</button>
              )}
            </>}
            pad={false}>
            <table className="table vf-table erp-journal-lines">
              <thead><tr><th>{t("erpAccount")}</th><th className="num">{t("erpDebit")}</th><th className="num">{t("erpCredit2")}</th></tr></thead>
              <tbody>
                {j.lines?.map((l) => (
                  <tr key={l.id}>
                    <td><span className="tnum erp-muted">{l.account?.code}</span> {l.account?.name}</td>
                    <td className="num">{Number(l.debit) ? amount(l.debit) : ""}</td>
                    <td className="num">{Number(l.credit) ? amount(l.credit) : ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </GlassCard>
        ))}
      </div>
      <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />

      <Dialog open={!!reversing} onClose={() => setReversing(null)} busy={busy} icon="ph-arrow-u-up-left" tone="warn"
        title={reversing ? fill(t("erpReverseQ"), { number: reversing.number }) : ""} sub={t("erpJournalHint")}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setReversing(null)} disabled={busy}>{t("erpBack")}</button>
          <button className="btn btn-danger" onClick={reverse} disabled={busy || reason.trim().length < 3}>{t("erpReverse")}</button>
        </>}>
        <Field label={t("erpReason")} htmlFor="j-rev" required>
          <input id="j-rev" className="input" value={reason} onChange={(e) => setReason(e.target.value)} autoFocus />
        </Field>
        {actionError && <div className="field-error" role="alert">{actionError}</div>}
      </Dialog>
    </>
  );
}

function Trial() {
  const { t } = useApp();
  const [data, setData] = useState<TrialBalance | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { api.get<{ data: TrialBalance }>("/erp/trial-balance").then((r) => setData(r.data)).catch((e) => setError(e.message)); }, []);

  if (error) return <ErrorState message={error} />;
  if (!data) return <LoadingBlock />;

  return (
    <>
      <StatPills items={[
        { label: t("erpDebit"), value: amount(data.total_debit) },
        { label: t("erpCredit2"), value: amount(data.total_credit) },
        { label: t("erpStatus"), value: data.balanced ? t("erpBalanced") : t("erpUnbalanced"), tone: data.balanced ? "ok" : "bad", icon: data.balanced ? "ph-check-circle" : "ph-warning" },
      ]} />
      <div className="vf-table-wrap">
        <table className="table vf-table">
          <thead><tr><th>{t("erpCode")}</th><th>{t("erpAccount")}</th><th>{t("erpType")}</th><th className="num">{t("erpDebit")}</th><th className="num">{t("erpCredit2")}</th><th className="num">{t("erpBalance")}</th></tr></thead>
          <tbody>
            {data.rows.map((r) => (
              <tr key={r.account_id}>
                <td className="tnum">{r.code}</td><td>{r.name}</td><td>{t(ACCOUNT_TYPE_LABEL[r.type])}</td>
                <td className="num">{amount(r.debit)}</td><td className="num">{amount(r.credit)}</td><td className="num"><strong>{amount(r.balance)}</strong></td>
              </tr>
            ))}
          </tbody>
          <tfoot><tr><td colSpan={3}><strong>{t("erpTotal")}</strong></td><td className="num"><strong>{amount(data.total_debit)}</strong></td><td className="num"><strong>{amount(data.total_credit)}</strong></td><td /></tr></tfoot>
        </table>
      </div>
    </>
  );
}

function JournalDialog({ accounts, onClose, onPosted }: { accounts: Account[]; onClose: () => void; onPosted: () => void }) {
  const { t, toast } = useApp();
  const [memo, setMemo] = useState("");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [lines, setLines] = useState([{ account_id: "", debit: "", credit: "" }, { account_id: "", debit: "", credit: "" }]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const active = useMemo(() => accounts.filter((a) => a.is_active), [accounts]);

  const debits = lines.reduce((s, l) => s + Number(l.debit || 0), 0);
  const credits = lines.reduce((s, l) => s + Number(l.credit || 0), 0);
  const balanced = debits > 0 && Math.abs(debits - credits) < 0.005;
  const setLine = (i: number, patch: Partial<(typeof lines)[number]>) => setLines((all) => all.map((l, j) => (j === i ? { ...l, ...patch } : l)));

  async function post() {
    setBusy(true); setError(null);
    try {
      const r = await api.post<{ message: string }>("/erp/journals", {
        memo, entry_date: date,
        lines: lines.filter((l) => l.account_id).map((l) => ({ account_id: Number(l.account_id), debit: Number(l.debit || 0), credit: Number(l.credit || 0) })),
      });
      toast(r.message, memo, "ok");
      onPosted();
    } catch (e) { setError(e instanceof ApiError ? e.message : String(e)); } finally { setBusy(false); }
  }

  return (
    <Dialog open wide title={t("erpNewJournal")} sub={t("erpJournalHint")} onClose={onClose} busy={busy}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpCancel")}</button>
        <button className="btn btn-primary" onClick={post} disabled={busy || !balanced || !memo.trim()}>{t("erpPost")}</button>
      </>}>
      <div className="erp-form-grid">
        <Field label={t("erpMemo")} htmlFor="j-memo" required><input id="j-memo" className="input" value={memo} onChange={(e) => setMemo(e.target.value)} /></Field>
        <Field label={t("erpDate")} htmlFor="j-date"><input id="j-date" className="input" type="date" value={date} onChange={(e) => setDate(e.target.value)} /></Field>
      </div>
      <table className="table vf-table erp-lines">
        <thead><tr><th>{t("erpAccount")}</th><th className="num">{t("erpDebit")}</th><th className="num">{t("erpCredit2")}</th><th aria-label={t("erpRemove")} /></tr></thead>
        <tbody>
          {lines.map((l, i) => (
            <tr key={i}>
              <td>
                <select className="input" aria-label={t("erpAccount")} value={l.account_id} onChange={(e) => setLine(i, { account_id: e.target.value })}>
                  <option value="">-</option>
                  {active.map((a) => <option key={a.id} value={a.id}>{a.code} · {a.name}</option>)}
                </select>
              </td>
              <td className="num"><input className="input tnum" type="number" min={0} step="0.01" aria-label={t("erpDebit")} value={l.debit} onChange={(e) => setLine(i, { debit: e.target.value, credit: e.target.value ? "" : l.credit })} /></td>
              <td className="num"><input className="input tnum" type="number" min={0} step="0.01" aria-label={t("erpCredit2")} value={l.credit} onChange={(e) => setLine(i, { credit: e.target.value, debit: e.target.value ? "" : l.debit })} /></td>
              <td><button type="button" className="btn btn-icon" aria-label={t("erpRemove")} disabled={lines.length <= 2} onClick={() => setLines((all) => all.filter((_, j) => j !== i))}><Icon name="ph-trash" size={17} /></button></td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr>
            <td><button type="button" className="btn btn-secondary btn-sm" onClick={() => setLines((all) => [...all, { account_id: "", debit: "", credit: "" }])}><Icon name="ph-plus" size={15} /> {t("erpAddLine")}</button></td>
            <td className="num"><strong>{amount(debits)}</strong></td>
            <td className="num"><strong>{amount(credits)}</strong></td>
            <td />
          </tr>
        </tfoot>
      </table>
      <div className="erp-balance-line">
        {balanced ? <Badge tone="ok" dot>{t("erpBalanced")}</Badge> : <Badge tone="warn" dot>{t("erpDifference")}: {amount(Math.abs(debits - credits))}</Badge>}
      </div>
      {error && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {error}</div>}
    </Dialog>
  );
}

"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, useErp } from "@/lib/erp";
import { type AccountRef, periodLabel } from "@/lib/finance-api";
import { Banner, ErrorState, Field, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { FinanceTabs } from "@/components/finance-ui";

export default function BudgetsPage() {
  return <ErpGate module="accounting" permission="finance.view"><Budgets /></ErpGate>;
}

interface BudgetData {
  fiscal_year: number; months: string[];
  budget: { id: number; name: string; notes: string | null; updated_at: string } | null;
  lines: { account_id: number; months: number[]; total: number }[];
  accounts: (AccountRef & { type: "income" | "expense" })[];
}

function Budgets() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const [year, setYear] = useState(new Date().getFullYear());
  const [data, setData] = useState<BudgetData | null>(null);
  const [grid, setGrid] = useState<Record<number, string[]>>({});
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [dirty, setDirty] = useState(false);
  const editable = can("finance.budget");

  const load = useCallback(() => {
    api.get<{ data: BudgetData }>(`/erp/finance/budgets/${year}`).then((r) => {
      setData(r.data); setError(null);
      setName(r.data.budget?.name ?? "");
      const g: Record<number, string[]> = {};
      for (const a of r.data.accounts) g[a.id] = Array(12).fill("");
      for (const l of r.data.lines) g[l.account_id] = l.months.map((m) => (m ? String(m) : ""));
      setGrid(g); setDirty(false);
    }).catch((e) => setError(e.message));
  }, [year]);
  useEffect(load, [load]);

  const totals = useMemo(() => {
    const byAccount: Record<number, number> = {};
    for (const [id, months] of Object.entries(grid)) byAccount[Number(id)] = months.reduce((s, m) => s + Number(m || 0), 0);
    return byAccount;
  }, [grid]);

  async function save() {
    if (!data) return;
    setBusy(true); setSaveError(null);
    try {
      const lines = Object.entries(grid).filter(([, months]) => months.some((m) => Number(m))).map(([id, months]) => ({ account_id: Number(id), months: months.map((m) => Number(m || 0)) }));
      await api.put(`/erp/finance/budgets/${year}`, { name: name || null, lines });
      toast(t("erpSaved"), `${t("finBudget")} ${year}`, "ok");
      load();
    } catch (e) { setSaveError(e instanceof ApiError ? e.message : String(e)); } finally { setBusy(false); }
  }

  const setCell = (id: number, i: number, v: string) => { setGrid((g) => ({ ...g, [id]: g[id].map((m, j) => (j === i ? v : m)) })); setDirty(true); };
  const spread = (id: number) => { const total = totals[id] || 0; setGrid((g) => ({ ...g, [id]: Array(12).fill(String(Math.round((total / 12) * 100) / 100)) })); setDirty(true); };

  return (
    <div className="erp-page">
      <PageHeader title={t("finTabBudgets")} subtitle={t("finBudgetsSub")}
        actions={editable && <button className="btn btn-primary" onClick={save} disabled={busy || !dirty}><Icon name="ph-floppy-disk" size={17} /> {t("erpSave")}</button>} />
      <FinanceTabs />

      <div className="fin-filters">
        <Field label={t("finFiscalYear")} htmlFor="b-year"><input id="b-year" type="number" className="input tnum" value={year} onChange={(e) => setYear(Number(e.target.value))} /></Field>
        <Field label={t("erpName")} htmlFor="b-name"><input id="b-name" className="input" value={name} disabled={!editable} onChange={(e) => { setName(e.target.value); setDirty(true); }} placeholder={`${t("finBudget")} ${year}`} /></Field>
      </div>
      {saveError && <Banner tone="danger" icon="ph-warning">{saveError}</Banner>}

      {error ? <ErrorState message={error} onRetry={load} /> : !data || data.fiscal_year !== year ? <LoadingBlock rows={8} /> : (
        <div className="vf-table-wrap fin-budget-grid">
          <table className="table vf-table">
            <thead><tr><th>{t("erpAccount")}</th>{data.months.map((m) => <th key={m} className="num">{periodLabel(m, locale)}</th>)}<th className="num">{t("erpTotal")}</th>{editable && <th />}</tr></thead>
            <tbody>
              {(["income", "expense"] as const).map((type) => [
                <tr key={type} className="fin-section"><td colSpan={data.months.length + (editable ? 3 : 2)}>{t(type === "income" ? "finIncome" : "finExpenses")}</td></tr>,
                ...data.accounts.filter((a) => a.type === type).map((a) => (
                  <tr key={a.id}>
                    <td><span className="tnum erp-muted">{a.code}</span> {a.name}</td>
                    {(grid[a.id] ?? []).map((v, i) => (
                      <td key={i}>{editable
                        ? <input className="input tnum" inputMode="decimal" aria-label={`${a.name} ${data.months[i]}`} value={v} onChange={(e) => setCell(a.id, i, e.target.value)} />
                        : <span className="tnum">{v ? amount(v) : ""}</span>}</td>
                    ))}
                    <td className="num"><strong className="tnum">{amount(totals[a.id] ?? 0)}</strong></td>
                    {editable && <td><button className="btn btn-secondary btn-sm" title={t("finSpreadEvenly")} aria-label={t("finSpreadEvenly")} onClick={() => spread(a.id)}><Icon name="ph-equals" size={14} /></button></td>}
                  </tr>
                )),
              ])}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

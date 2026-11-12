"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, useErp, useQueryValue } from "@/lib/erp";
import type { BankAccount, CashbookEntry, CashbookType, FinStatus } from "@/lib/finance-api";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination, StatPills } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { DocStatus, ErpGate, FilterChips } from "@/components/erp-ui";
import { Flow, FinanceTabs } from "@/components/finance-ui";
import { CashbookDialog } from "@/components/finance-cashbook-form";

export default function CashbookPage() {
  return <ErpGate module="accounting" permission="finance.view"><Cashbook /></ErpGate>;
}

type Page = Paginated<CashbookEntry> & { totals: { receipts: number; payments: number } };

function Cashbook() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const router = useRouter();
  const wantsNew = useQueryValue("new");
  const [type, setType] = useState<CashbookType | "">("");
  const [status, setStatus] = useState<FinStatus | "">("");
  const [bank, setBank] = useState("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Page | null>(null);
  const [banks, setBanks] = useState<BankAccount[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [chosen, setCreating] = useState<CashbookType | null | undefined>(undefined);

  useEffect(() => { api.get<{ data: BankAccount[] }>("/erp/finance/bank-accounts").then((r) => setBanks(r.data)).catch(() => setBanks([])); }, []);
  const creating = chosen !== undefined ? chosen : (wantsNew === "receipt" || wantsNew === "payment") && can("finance.cashbook") ? wantsNew : null;
  useEffect(() => {
    const id = window.setTimeout(() => {
      api.get<Page>("/erp/finance/cashbook", { type: type || undefined, status: status || undefined, bank_account_id: bank || undefined, from: from || undefined, to: to || undefined, q: q || undefined, page })
        .then(setRows).catch((e) => setError(e.message));
    }, q ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [type, status, bank, from, to, q, page]);

  const reset = () => setPage(1);

  return (
    <div className="erp-page">
      <PageHeader title={t("finTabCashbook")} subtitle={t("finCashbookSub")}
        actions={can("finance.cashbook") && <>
          <button className="btn btn-secondary" onClick={() => setCreating("payment")}><Icon name="ph-arrow-up-right" size={17} /> {t("finNewPayment")}</button>
          <button className="btn btn-primary" onClick={() => setCreating("receipt")}><Icon name="ph-arrow-down-left" size={17} /> {t("finNewReceipt")}</button>
        </>} />
      <FinanceTabs />

      {rows && <StatPills items={[
        { label: t("finReceiptsPosted"), value: amount(rows.totals.receipts), icon: "ph-arrow-down-left", tone: "ok" },
        { label: t("finPaymentsPosted"), value: amount(rows.totals.payments), icon: "ph-arrow-up-right" },
        { label: t("finNet"), value: amount(rows.totals.receipts - rows.totals.payments), icon: "ph-scales" },
      ]} />}

      <Toolbar end={
        <select className="input" aria-label={t("finBankAccount")} value={bank} onChange={(e) => { setBank(e.target.value); reset(); }} style={{ maxWidth: 220 }}>
          <option value="">{t("finAllAccounts")}</option>
          {banks.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
        </select>
      }>
        <SearchInput value={q} onChange={(v) => { setQ(v); reset(); }} placeholder={`${t("erpSearch")}, ${t("finDescription")}`} />
        <FilterChips<CashbookType | ""> value={type} onChange={(v) => { setType(v); reset(); }} items={[
          { value: "", label: t("erpAll") }, { value: "receipt", label: t("finReceipts") }, { value: "payment", label: t("finPayments") },
        ]} />
        <FilterChips<FinStatus | ""> value={status} onChange={(v) => { setStatus(v); reset(); }} items={[
          { value: "", label: t("erpAll") }, { value: "draft", label: t("erpStatusDraft") }, { value: "posted", label: t("erpStatusPosted") }, { value: "reversed", label: t("erpStatusReversed") },
        ]} />
      </Toolbar>
      <div className="fin-filters">
        <Field label={t("finFrom")} htmlFor="cb-from"><input id="cb-from" type="date" className="input" value={from} onChange={(e) => { setFrom(e.target.value); reset(); }} /></Field>
        <Field label={t("finTo")} htmlFor="cb-to"><input id="cb-to" type="date" className="input" value={to} onChange={(e) => { setTo(e.target.value); reset(); }} /></Field>
      </div>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-book-open-text" title={t("finNoEntries")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpReference")}</th><th>{t("finDescription")}</th><th>{t("erpAccount")}</th><th>{t("finBankAccount")}</th><th>{t("erpDate")}</th><th className="num">{t("finAmount")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((e) => (
                  <tr key={e.id} className="is-clickable" onClick={() => router.push(`/erp/finance/cashbook/${e.id}`)}>
                    <td><Link className="erp-cell-link" href={`/erp/finance/cashbook/${e.id}`}><span className="erp-cell-title tnum">{e.number}</span>{e.reference && <span className="erp-cell-sub">{e.reference}</span>}</Link></td>
                    <td>{e.description}{e.counterparty && <span className="erp-cell-sub">{e.counterparty}</span>}</td>
                    <td><span className="tnum erp-muted">{e.account?.code}</span> {e.account?.name}</td>
                    <td>{e.bank_account?.name}</td>
                    <td className="tnum">{formatDate(e.entry_date, locale)}</td>
                    <td className="num"><Flow value={e.type === "payment" ? -Number(e.amount) : Number(e.amount)} /></td>
                    <td><DocStatus status={e.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      {creating && <CashbookDialog entry={null} type={creating} onClose={() => setCreating(null)} onSaved={(e) => router.push(`/erp/finance/cashbook/${e.id}`)} />}
    </div>
  );
}

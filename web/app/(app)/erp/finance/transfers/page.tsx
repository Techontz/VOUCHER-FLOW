"use client";

import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, useErp } from "@/lib/erp";
import { type BankAccount, type BankTransfer, type FinStatus, today } from "@/lib/finance-api";
import { formatDate, formatDateTime } from "@/lib/format";
import { Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { DocStatus, ErpGate, FilterChips } from "@/components/erp-ui";
import { FinanceTabs, JournalLines } from "@/components/finance-ui";

export default function TransfersPage() {
  return <ErpGate module="accounting" permission="finance.view"><Transfers /></ErpGate>;
}

function Transfers() {
  const { t, locale } = useApp();
  const { can } = useErp();
  const [status, setStatus] = useState<FinStatus | "">("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<BankTransfer> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [banks, setBanks] = useState<BankAccount[]>([]);
  const [form, setForm] = useState<BankTransfer | "new" | null>(null);
  const [open, setOpen] = useState<BankTransfer | null>(null);
  const [version, setVersion] = useState(0);

  useEffect(() => { api.get<{ data: BankAccount[] }>("/erp/finance/bank-accounts", { active: 1 }).then((r) => setBanks(r.data)).catch(() => setBanks([])); }, []);
  useEffect(() => {
    const id = window.setTimeout(() => {
      api.get<Paginated<BankTransfer>>("/erp/finance/transfers", { status: status || undefined, q: q || undefined, page })
        .then(setRows).catch((e) => setError(e.message));
    }, q ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [status, q, page, version]);

  const reload = () => setVersion((v) => v + 1);

  return (
    <div className="erp-page">
      <PageHeader title={t("finTabTransfers")} subtitle={t("finTransfersSub")}
        actions={can("finance.bank") && <button className="btn btn-primary" onClick={() => setForm("new")}><Icon name="ph-plus" size={18} /> {t("finNewTransfer")}</button>} />
      <FinanceTabs />

      <Toolbar>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={`${t("erpSearch")}, ${t("erpReference")}`} />
        <FilterChips<FinStatus | ""> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "", label: t("erpAll") }, { value: "draft", label: t("erpStatusDraft") },
          { value: "posted", label: t("erpStatusPosted") }, { value: "reversed", label: t("erpStatusReversed") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? <EmptyState icon="ph-arrows-left-right" title={t("finNoTransfers")} /> : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpReference")}</th><th>{t("finFromAccount")}</th><th>{t("finToAccount")}</th><th>{t("erpDate")}</th><th className="num">{t("finAmount")}</th><th className="num">{t("finCharges")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((r) => (
                  <tr key={r.id} className="is-clickable" onClick={() => setOpen(r)}>
                    <td><button type="button" className="erp-cell-link" onClick={() => setOpen(r)}><span className="erp-cell-title tnum">{r.number}</span>{r.reference && <span className="erp-cell-sub">{r.reference}</span>}</button></td>
                    <td>{r.from?.name}</td><td>{r.to?.name}</td>
                    <td className="tnum">{formatDate(r.transfer_date, locale)}</td>
                    <td className="num">{amount(r.amount)}</td><td className="num">{Number(r.charges) ? amount(r.charges) : ""}</td>
                    <td><DocStatus status={r.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      {form && <TransferForm transfer={form === "new" ? null : form} banks={banks} onClose={() => setForm(null)} onSaved={(tr) => { setForm(null); reload(); setOpen(tr); }} />}
      {open && <TransferDetail id={open.id} onClose={() => setOpen(null)} onChanged={reload} onEdit={(tr) => { setOpen(null); setForm(tr); }} />}
    </div>
  );
}

function TransferForm({ transfer, banks, onClose, onSaved }: { transfer: BankTransfer | null; banks: BankAccount[]; onClose: () => void; onSaved: (t: BankTransfer) => void }) {
  const { t, toast } = useApp();
  const [form, setForm] = useState({
    transfer_date: transfer?.transfer_date.slice(0, 10) ?? today(),
    from_bank_account_id: String(transfer?.from_bank_account_id ?? ""), to_bank_account_id: String(transfer?.to_bank_account_id ?? ""),
    amount: transfer?.amount ?? "", charges: transfer && Number(transfer.charges) ? transfer.charges : "", reference: transfer?.reference ?? "", memo: transfer?.memo ?? "",
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const set = (patch: Partial<typeof form>) => setForm((f) => ({ ...f, ...patch }));

  async function save() {
    setBusy(true); setError(null);
    try {
      const body = { ...form, charges: form.charges || 0, reference: form.reference || null, memo: form.memo || null };
      const r = transfer
        ? await api.put<{ data: BankTransfer }>(`/erp/finance/transfers/${transfer.id}`, body)
        : await api.post<{ data: BankTransfer }>("/erp/finance/transfers", body);
      toast(t("erpSaved"), r.data.number, "ok");
      onSaved(r.data);
    } catch (e) { setError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  return (
    <Dialog open title={transfer ? transfer.number : t("finNewTransfer")} sub={t("finTransferHint")} onClose={onClose} busy={busy}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpCancel")}</button>
        <button className="btn btn-primary" onClick={save} disabled={busy || !form.from_bank_account_id || !form.to_bank_account_id || !form.amount}>{t("finSaveDraft")}</button>
      </>}>
      {error && !Object.keys(error.errors).length && <div className="field-error" role="alert">{error.message}</div>}
      <div className="erp-form-grid">
        <Field label={t("finFromAccount")} htmlFor="t-from" required error={error?.field("from_bank_account_id")}>
          <select id="t-from" className="input" value={form.from_bank_account_id} onChange={(e) => set({ from_bank_account_id: e.target.value })}>
            <option value="">{t("finChoose")}</option>
            {banks.map((b) => <option key={b.id} value={b.id}>{b.name} ({amount(b.balance)})</option>)}
          </select>
        </Field>
        <Field label={t("finToAccount")} htmlFor="t-to" required error={error?.field("to_bank_account_id")}>
          <select id="t-to" className="input" value={form.to_bank_account_id} onChange={(e) => set({ to_bank_account_id: e.target.value })}>
            <option value="">{t("finChoose")}</option>
            {banks.filter((b) => String(b.id) !== form.from_bank_account_id).map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
        </Field>
        <Field label={t("erpDate")} htmlFor="t-date" required error={error?.field("transfer_date")}>
          <input id="t-date" type="date" className="input" max={today()} value={form.transfer_date} onChange={(e) => set({ transfer_date: e.target.value })} />
        </Field>
        <Field label={t("finAmount")} htmlFor="t-amt" required error={error?.field("amount")}>
          <input id="t-amt" className="input tnum" inputMode="decimal" value={form.amount} onChange={(e) => set({ amount: e.target.value })} />
        </Field>
        <Field label={t("finCharges")} htmlFor="t-chg" hint={t("finChargesHint")} error={error?.field("charges")}>
          <input id="t-chg" className="input tnum" inputMode="decimal" value={form.charges} onChange={(e) => set({ charges: e.target.value })} />
        </Field>
        <Field label={t("erpReference")} htmlFor="t-ref" error={error?.field("reference")}>
          <input id="t-ref" className="input" value={form.reference} onChange={(e) => set({ reference: e.target.value })} />
        </Field>
        <Field label={t("finMemo")} htmlFor="t-memo" error={error?.field("memo")}>
          <input id="t-memo" className="input" value={form.memo} onChange={(e) => set({ memo: e.target.value })} />
        </Field>
      </div>
    </Dialog>
  );
}

function TransferDetail({ id, onClose, onChanged, onEdit }: { id: number; onClose: () => void; onChanged: () => void; onEdit: (t: BankTransfer) => void }) {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const [tr, setTr] = useState<BankTransfer | null>(null);
  const [confirm, setConfirm] = useState<"post" | "reverse" | "cancel" | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => { api.get<{ data: BankTransfer }>(`/erp/finance/transfers/${id}`).then((r) => setTr(r.data)).catch((e) => setError(e.message)); }, [id]);
  useEffect(load, [load]);

  async function act() {
    if (!tr || !confirm) return;
    setBusy(true); setError(null);
    try {
      const r = await api.post<{ message: string }>(`/erp/finance/transfers/${tr.id}/${confirm}`, confirm === "reverse" ? { reason } : undefined);
      toast(r.message, undefined, "ok");
      setConfirm(null); setReason(""); load(); onChanged();
    } catch (e) { setError(e instanceof ApiError ? e.message : String(e)); } finally { setBusy(false); }
  }

  const manage = can("finance.bank");

  return (
    <Dialog open title={tr?.number ?? ""} onClose={onClose} busy={busy} wide icon="ph-arrows-left-right"
      summary={tr ? [
        { label: t("finFromAccount"), value: tr.from?.name },
        { label: t("finToAccount"), value: tr.to?.name },
        { label: t("erpDate"), value: formatDate(tr.transfer_date, locale) },
        { label: t("finAmount"), value: amount(tr.amount) },
        { label: t("finCharges"), value: amount(tr.charges) },
        { label: t("erpStatus"), value: <DocStatus status={tr.status} /> },
      ] : undefined}
      actions={tr && !confirm ? <>
        {tr.status === "draft" && manage && <button className="btn btn-secondary" onClick={() => onEdit(tr)}><Icon name="ph-pencil-simple" size={16} /> {t("erpEdit")}</button>}
        {tr.status === "draft" && manage && <button className="btn btn-secondary" onClick={() => setConfirm("cancel")}>{t("erpCancelDraft")}</button>}
        {tr.status === "draft" && manage && <button className="btn btn-primary" onClick={() => setConfirm("post")}><Icon name="ph-check-circle" size={17} /> {t("erpPost")}</button>}
        {tr.status === "posted" && manage && <button className="btn btn-secondary" onClick={() => setConfirm("reverse")}><Icon name="ph-arrow-u-up-left" size={16} /> {t("erpReverse")}</button>}
      </> : confirm ? <>
        <button className="btn btn-secondary" onClick={() => setConfirm(null)} disabled={busy}>{t("erpBack")}</button>
        <button className={confirm === "post" ? "btn btn-primary" : "btn btn-danger"} onClick={act} disabled={busy || (confirm === "reverse" && reason.trim().length < 3)}>
          {t(confirm === "post" ? "erpPost" : confirm === "reverse" ? "erpReverse" : "erpCancelDraft")}
        </button>
      </> : undefined}>
      {!tr ? <LoadingBlock rows={3} /> : <>
        {tr.memo && <p className="erp-muted">{tr.memo}</p>}
        {confirm === "post" && <p>{t("finPostTransferQ")}</p>}
        {confirm === "reverse" && (
          <Field label={t("erpReason")} htmlFor="tr-reason" required>
            <input id="tr-reason" className="input" value={reason} onChange={(e) => setReason(e.target.value)} autoFocus />
          </Field>
        )}
        {tr.journal?.lines && <JournalLines lines={tr.journal.lines} number={tr.journal.number} />}
        <p className="erp-muted">
          {tr.creator && <>{t("erpPrepared")}: {tr.creator.name}. </>}
          {tr.poster && tr.posted_at && <>{t("erpStatusPosted")}: {tr.poster.name}, {formatDateTime(tr.posted_at, locale)}. </>}
          {tr.reverser && tr.reversed_at && <>{t("erpStatusReversed")}: {tr.reverser.name}, {formatDateTime(tr.reversed_at, locale)} ({tr.reversal_reason}).</>}
        </p>
      </>}
      {error && <div className="field-error" role="alert">{error}</div>}
    </Dialog>
  );
}

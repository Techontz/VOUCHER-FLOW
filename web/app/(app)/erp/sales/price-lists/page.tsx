"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import type { PriceListRow } from "@/lib/sales-api";
import { Badge, Dialog, EmptyState, ErrorState, Field, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Check, ErpGate } from "@/components/erp-ui";

export default function PriceListsPage() {
  return <ErpGate module="sales" permission="sales.view"><PriceLists /></ErpGate>;
}

function PriceLists() {
  const { t, toast } = useApp();
  const { can } = useErp();
  const [rows, setRows] = useState<PriceListRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({ code: "", name: "", is_default: false, notes: "" });
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  const load = useCallback(() => {
    api.get<{ data: PriceListRow[] }>("/erp/sales/price-lists").then((r) => setRows(r.data)).catch((e) => setError(e.message));
  }, []);
  useEffect(load, [load]);

  async function create() {
    setBusy(true); setFormError(null);
    try {
      await api.post("/erp/sales/price-lists", { ...form, code: form.code.toUpperCase(), notes: form.notes || null });
      toast(t("erpSaved"), form.name, "ok");
      setOpen(false); setForm({ code: "", name: "", is_default: false, notes: "" });
      load();
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="erp-page">
      <PageHeader title={t("salPriceLists")} subtitle={t("salPriceListsSub")}
        actions={can("sales.pricing") && <button className="btn btn-primary" onClick={() => setOpen(true)}><Icon name="ph-plus" size={18} /> {t("salNewPriceList")}</button>} />
      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.length === 0 ? <EmptyState icon="ph-tag" title={t("salNoPriceLists")} body={t("salNoPriceListsBody")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("salPriceList")}</th><th>{t("salCode")}</th><th className="num">{t("salPrices")}</th><th className="num">{t("salCustomers")}</th><th>{t("erpStatus")}</th></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td><Link className="erp-cell-link" href={`/erp/sales/price-lists/${r.id}`}><span className="erp-cell-title">{r.name}</span>{r.notes && <span className="erp-cell-sub">{r.notes}</span>}</Link></td>
                  <td className="tnum">{r.code}</td>
                  <td className="num">{r.items_count}</td>
                  <td className="num">{r.customers_count}</td>
                  <td>{r.is_default && <Badge tone="info">{t("salDefault")}</Badge>} {!r.is_active && <Badge>{t("salInactive")}</Badge>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <Dialog open={open} title={t("salNewPriceList")} onClose={() => setOpen(false)} busy={busy}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setOpen(false)} disabled={busy}>{t("erpCancel")}</button>
          <button className="btn btn-primary" onClick={create} disabled={busy || !form.code || !form.name}>{t("erpSave")}</button>
        </>}>
        <Field label={t("salCode")} htmlFor="pl-code" required error={formError?.field("code")} hint={t("salCodeHint")}>
          <input id="pl-code" className="input" value={form.code} onChange={(e) => setForm((f) => ({ ...f, code: e.target.value }))} />
        </Field>
        <Field label={t("salName")} htmlFor="pl-name" required error={formError?.field("name")}>
          <input id="pl-name" className="input" value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
        </Field>
        <Field label={t("salNotes")} htmlFor="pl-notes" hint={t("erpOptional")}>
          <input id="pl-notes" className="input" value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
        </Field>
        <Check label={t("salMakeDefault")} hint={t("salMakeDefaultHint")} checked={form.is_default} onChange={(v) => setForm((f) => ({ ...f, is_default: v }))} />
        {formError && !formError.field("code") && !formError.field("name") && <div className="field-error" role="alert">{formError.message}</div>}
      </Dialog>
    </div>
  );
}

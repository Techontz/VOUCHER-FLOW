"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { type PriceListRow, useSalesLookups } from "@/lib/sales-api";
import { Badge, EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Check, ErpGate } from "@/components/erp-ui";
import { Money } from "@/components/sales-ui";

export default function PriceListPage() {
  return <ErpGate module="sales" permission="sales.view"><PriceListDetail /></ErpGate>;
}

interface Item { product_id: string; unit_price: string; effective_from: string; effective_to: string }

/**
 * A list's dated prices, and which customers buy from it. A new row for a
 * product from a later date supersedes the old price from that date on, so
 * the history of a price stays readable.
 */
function PriceListDetail() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const { id } = useParams<{ id: string }>();
  const { lookups } = useSalesLookups();
  const [list, setList] = useState<PriceListRow | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Item[] | null>(null);
  const [assigning, setAssigning] = useState<number[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const load = useCallback(() => {
    api.get<{ data: PriceListRow }>(`/erp/sales/price-lists/${id}`).then((r) => setList(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  if (error) return <ErrorState message={error} />;
  if (!list) return <LoadingBlock rows={5} />;

  const today = new Date().toISOString().slice(0, 10);
  const pricing = can("sales.pricing");

  async function send(path: string, body: unknown) {
    setBusy(true); setFormError(null);
    try {
      const r = await api.put<{ data: PriceListRow }>(path, body);
      setList(r.data); setEditing(null); setAssigning(null);
      toast(t("erpSaved"), undefined, "ok");
    } catch (e) {
      setFormError(e instanceof ApiError ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function toggle(field: "is_default" | "is_active", value: boolean) {
    try {
      await api.put(`/erp/sales/price-lists/${list!.id}`, { code: list!.code, name: list!.name, notes: list!.notes, [field]: value });
      load();
    } catch (e) {
      toast(e instanceof ApiError ? e.message : String(e), undefined, "bad");
    }
  }

  return (
    <div className="erp-page">
      <PageHeader back={<Link href="/erp/sales/price-lists" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("salPriceLists")}</Link>}
        kicker={list.code} title={list.name} subtitle={list.notes ?? undefined}
        actions={<>
          {list.is_default && <Badge tone="info">{t("salDefault")}</Badge>}
          {pricing && !editing && <button className="btn btn-primary" onClick={() => setEditing((list.items ?? []).map((i) => ({ product_id: String(i.product_id), unit_price: String(Number(i.unit_price)), effective_from: i.effective_from.slice(0, 10), effective_to: i.effective_to?.slice(0, 10) ?? "" })))}><Icon name="ph-pencil-simple" size={17} /> {t("salEditPrices")}</button>}
        </>} />

      {pricing && (
        <GlassCard>
          <Check label={t("salMakeDefault")} hint={t("salMakeDefaultHint")} checked={list.is_default} onChange={(v) => void toggle("is_default", v)} />
          <Check label={t("salActive")} checked={list.is_active} onChange={(v) => void toggle("is_active", v)} />
        </GlassCard>
      )}

      <GlassCard title={t("salPrices")} pad={false}>
        {editing ? (
          <>
            <div className="vf-table-wrap">
              <table className="table vf-table erp-lines">
                <thead><tr><th>{t("erpProduct")}</th><th className="num">{t("salUnitPrice")}</th><th>{t("salEffectiveFrom")}</th><th>{t("salEffectiveTo")}</th><th /></tr></thead>
                <tbody>
                  {editing.map((row, i) => (
                    <tr key={i}>
                      <td>
                        <select className="input" aria-label={t("erpProduct")} value={row.product_id} onChange={(e) => setEditing((all) => all!.map((r, j) => (j === i ? { ...r, product_id: e.target.value } : r)))}>
                          <option value="">{t("erpPickProduct")}</option>
                          {lookups?.products.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.sku}</option>)}
                        </select>
                      </td>
                      <td className="num"><input className="input tnum" type="number" min={0} step="any" aria-label={t("salUnitPrice")} value={row.unit_price} onChange={(e) => setEditing((all) => all!.map((r, j) => (j === i ? { ...r, unit_price: e.target.value } : r)))} /></td>
                      <td><input className="input" type="date" aria-label={t("salEffectiveFrom")} value={row.effective_from} onChange={(e) => setEditing((all) => all!.map((r, j) => (j === i ? { ...r, effective_from: e.target.value } : r)))} /></td>
                      <td><input className="input" type="date" aria-label={t("salEffectiveTo")} value={row.effective_to} onChange={(e) => setEditing((all) => all!.map((r, j) => (j === i ? { ...r, effective_to: e.target.value } : r)))} /></td>
                      <td><button className="btn btn-icon" aria-label={t("erpRemove")} onClick={() => setEditing((all) => all!.filter((_, j) => j !== i))}><Icon name="ph-trash" size={17} /></button></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="erp-lines-foot">
              <button className="btn btn-secondary btn-sm" onClick={() => setEditing((all) => [...all!, { product_id: "", unit_price: "", effective_from: today, effective_to: "" }])}><Icon name="ph-plus" size={16} /> {t("erpAddLine")}</button>
              <span className="sal-row-actions">
                <button className="btn btn-secondary" onClick={() => { setEditing(null); setFormError(null); }} disabled={busy}>{t("erpCancel")}</button>
                <button className="btn btn-primary" disabled={busy} onClick={() => void send(`/erp/sales/price-lists/${list.id}/items`, {
                  items: editing.filter((r) => r.product_id && r.unit_price !== "").map((r) => ({ product_id: Number(r.product_id), unit_price: Number(r.unit_price), effective_from: r.effective_from, effective_to: r.effective_to || null })),
                })}>{t("erpSave")}</button>
              </span>
            </div>
          </>
        ) : (list.items?.length ?? 0) === 0 ? <EmptyState icon="ph-tag" title={t("salNoPrices")} /> : (
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpProduct")}</th><th className="num">{t("salUnitPrice")}</th><th className="num">{t("salProductPrice")}</th><th>{t("salEffectiveFrom")}</th><th>{t("salEffectiveTo")}</th><th /></tr></thead>
              <tbody>
                {list.items!.map((i) => {
                  const future = i.effective_from.slice(0, 10) > today;
                  const ended = i.effective_to && i.effective_to.slice(0, 10) < today;
                  return (
                    <tr key={i.id}>
                      <td>{i.product?.name}<span className="erp-cell-sub tnum">{i.product?.sku}</span></td>
                      <td className="num"><Money value={i.unit_price} strong /></td>
                      <td className="num erp-muted"><Money value={i.product?.sale_price} /></td>
                      <td className="tnum">{formatDate(i.effective_from, locale)}</td>
                      <td className="tnum">{formatDate(i.effective_to, locale)}</td>
                      <td>{future ? <Badge tone="info">{t("salUpcoming")}</Badge> : ended ? <Badge>{t("salEnded")}</Badge> : null}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        {formError && <div className="vf-alert tone-bad" role="alert" style={{ margin: 12 }}><Icon name="ph-warning-circle" size={18} /><span className="vf-alert-text">{formError}</span></div>}
      </GlassCard>

      <GlassCard title={t("salCustomers")} subtitle={t("salCustomersOnList")}
        action={pricing && !assigning && <button className="btn btn-secondary btn-sm" onClick={() => setAssigning((list.customers ?? []).map((c) => c.id))}>{t("salChooseCustomers")}</button>}>
        {assigning ? (
          <>
            <div className="sal-check-grid">
              {lookups?.customers.map((c) => (
                <Check key={c.id} label={c.name} hint={c.price_list && c.price_list !== list.code ? `${t("salNowOn")} ${c.price_list}` : undefined}
                  checked={assigning.includes(c.id)} onChange={(v) => setAssigning((a) => (v ? [...a!, c.id] : a!.filter((x) => x !== c.id)))} />
              ))}
            </div>
            <div className="erp-stepnav">
              <button className="btn btn-secondary" onClick={() => setAssigning(null)} disabled={busy}>{t("erpCancel")}</button>
              <button className="btn btn-primary" disabled={busy} onClick={() => void send(`/erp/sales/price-lists/${list.id}/customers`, { customer_ids: assigning })}>{t("erpSave")}</button>
            </div>
          </>
        ) : (list.customers?.length ?? 0) === 0 ? <p className="erp-muted">{list.is_default ? t("salDefaultForEveryone") : t("salNoCustomersOnList")}</p> : (
          <ul className="erp-list">
            {list.customers!.map((c) => <li key={c.id} className="erp-list-row"><span className="erp-list-main"><span className="erp-list-title">{c.name}</span><span className="erp-list-sub">{c.code}{c.city ? ` · ${c.city}` : ""}</span></span><Link className="vf-card-link" href={`/erp/sales/statement?customer=${c.id}`}>{t("salStatement")}</Link></li>)}
          </ul>
        )}
      </GlassCard>
    </div>
  );
}

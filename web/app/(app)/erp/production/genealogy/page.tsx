"use client";

import Link from "next/link";
import { type FormEvent, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, qty, useQueryValue } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import type { Genealogy, GenealogyBatch } from "@/lib/production-api";
import { EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { OrderStatusBadge, ReceiptStatusBadge } from "@/components/production-ui";

type RecentBatch = GenealogyBatch & { product: { id: number; sku: string; name: string } | null; order_number: string | null };

export default function GenealogyPage() {
  return <ErpGate module="production" permission="production.view"><GenealogySearch /></ErpGate>;
}

/**
 * Traceability for recalls: type any batch number. A finished batch shows the
 * material batches its order consumed; a material batch shows every finished
 * batch made from the orders it went into.
 */
function GenealogySearch() {
  const { t, locale } = useApp();
  const initial = useQueryValue("batch");
  const [input, setInput] = useState("");
  const [batch, setBatch] = useState<string | null>(null);
  const [result, setResult] = useState<Genealogy | null>(null);
  const [recent, setRecent] = useState<RecentBatch[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const current = batch ?? initial ?? "";

  useEffect(() => {
    if (initial === undefined) return;
    if (!current) {
      api.get<{ recent: RecentBatch[] }>("/erp/production/genealogy").then((r) => setRecent(r.recent)).catch((e) => setError(e.message));
      return;
    }
    api.get<{ data: Genealogy }>("/erp/production/genealogy", { batch: current })
      .then((r) => { setResult(r.data); setError(null); })
      .catch((e) => setError(e.message));
  }, [current, initial]);

  function search(e: FormEvent) {
    e.preventDefault();
    const value = input.trim();
    setBatch(value);
    window.history.replaceState(null, "", value ? `?batch=${encodeURIComponent(value)}` : window.location.pathname);
  }

  function open(value: string) {
    setInput(value);
    setBatch(value);
    window.history.replaceState(null, "", `?batch=${encodeURIComponent(value)}`);
  }

  // Still loading while the result on screen belongs to another batch.
  const loading = !!current && !error && result?.batch !== current;
  const empty = result && result.as_finished.length === 0 && result.as_material.length === 0;

  return (
    <div className="erp-page">
      <PageHeader title={t("prdNavGenealogy")} subtitle={t("prdGenealogySub")} />

      <GlassCard>
        <form onSubmit={search} className="erp-field-row">
          <input className="input" aria-label={t("prdBatch")} placeholder={t("prdBatchSearchPlaceholder")} value={input}
            onChange={(e) => setInput(e.target.value)} />
          <button type="submit" className="btn btn-primary"><Icon name="ph-magnifying-glass" size={17} /> {t("prdTrace")}</button>
        </form>
      </GlassCard>

      {error && <ErrorState message={error} />}

      {!current && recent && (
        <GlassCard title={t("prdRecentBatches")} pad={false}>
          {recent.length === 0 ? <EmptyState icon="ph-tree-structure" title={t("prdNoReceipts")} /> : (
            <ul className="erp-list">
              {recent.map((r) => (
                <li key={r.id}>
                  <button type="button" className="erp-list-row" onClick={() => r.batch_number && open(r.batch_number)}>
                    <span className="erp-list-icon"><Icon name="ph-barcode" size={18} /></span>
                    <span className="erp-list-main">
                      <span className="erp-list-title tnum">{r.batch_number}</span>
                      <span className="erp-list-sub">{r.product?.name} · {r.order_number} · {formatDate(r.receipt_date, locale)}</span>
                    </span>
                    <ReceiptStatusBadge status={r.status} />
                  </button>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>
      )}

      {current && loading && <LoadingBlock rows={3} />}
      {current && !loading && empty && <EmptyState icon="ph-magnifying-glass" title={t("prdNoTrace")} body={t("prdNoTraceBody")} />}

      {current && !loading && result && result.as_finished.map((f) => (
        <GlassCard key={f.receipt.id} title={`${t("prdFinishedBatch")} ${f.receipt.batch_number}`}
          subtitle={<>{f.product?.name} · <Link href={`/erp/production/orders/${f.order.id}`}>{f.order.number}</Link> · {formatDate(f.receipt.receipt_date, locale)} · {qty(f.receipt.released_quantity)} {t("prdReleasedQty").toLowerCase()}</>}
          action={<ReceiptStatusBadge status={f.receipt.status} />} pad={false}>
          {f.materials.length === 0 ? <EmptyState icon="ph-tray" title={t("prdNoIssues")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("prdComponent")}</th><th>{t("prdMaterialBatch")}</th><th className="num">{t("erpQuantity")}</th><th className="num">{t("erpValue")}</th><th>{t("prdIssueDocs")}</th></tr></thead>
                <tbody>
                  {f.materials.map((m, i) => (
                    <tr key={i}>
                      <td><span className="erp-cell-title">{m.product?.name}</span><span className="erp-cell-sub tnum">{m.product?.sku}</span></td>
                      <td className="tnum">{m.batch_number ? <button type="button" className="btn btn-sm btn-secondary" onClick={() => open(m.batch_number!)}>{m.batch_number}</button> : <span className="erp-muted">{t("prdNotBatchTracked")}</span>}</td>
                      <td className="num">{qty(m.quantity)}</td>
                      <td className="num">{amount(m.value)}</td>
                      <td className="tnum">{m.references.join(", ")}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>
      ))}

      {current && !loading && result && result.as_material.map((m, i) => (
        <GlassCard key={i} title={`${t("prdMaterialBatch")} ${result.batch}`}
          subtitle={<>{m.material?.name} · {qty(m.quantity)} {t("prdIssuedTo")} {m.order ? <Link href={`/erp/production/orders/${m.order.id}`}>{m.order.number}</Link> : "-"} · {m.product?.name}</>}
          action={m.order ? <OrderStatusBadge status={m.order.status} /> : undefined} pad={false}>
          {m.finished_batches.length === 0 ? <EmptyState icon="ph-package" title={t("prdNoFinishedYet")} /> : (
            <ul className="erp-list">
              {m.finished_batches.map((b) => (
                <li key={b.id}>
                  <button type="button" className="erp-list-row" onClick={() => b.batch_number && open(b.batch_number)}>
                    <span className="erp-list-icon"><Icon name="ph-package" size={18} /></span>
                    <span className="erp-list-main">
                      <span className="erp-list-title tnum">{b.batch_number ?? b.number}</span>
                      <span className="erp-list-sub">{b.number} · {formatDate(b.receipt_date, locale)} · {qty(b.released_quantity)} / {qty(b.good_quantity)}{b.expiry_date ? ` · ${t("erpExpiry")} ${formatDate(b.expiry_date, locale)}` : ""}</span>
                    </span>
                    <ReceiptStatusBadge status={b.status} />
                  </button>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>
      ))}
    </div>
  );
}

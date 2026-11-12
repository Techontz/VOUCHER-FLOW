"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, DOCUMENT_ICON, PREPARE_PERMISSION, qty, type StockDocument, useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import { Dialog, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { DOC_LABEL, DocStatus, ErpGate, fill, SignedQty } from "@/components/erp-ui";
import { MovementTable } from "@/components/erp-movements";

export default function DocumentPage() {
  return <ErpGate module="inventory" permission="inventory.view"><DocumentDetail /></ErpGate>;
}

function DocumentDetail() {
  const { t, locale, toast } = useApp();
  const { can, config } = useErp();
  const router = useRouter();
  const { id } = useParams<{ id: string }>();
  const [doc, setDoc] = useState<StockDocument | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<"post" | "reverse" | "cancel" | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const load = useCallback(() => {
    api.get<{ data: StockDocument }>(`/erp/stock-documents/${id}`).then((r) => setDoc(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  async function act() {
    if (!doc || !confirm) return;
    setBusy(true); setActionError(null);
    try {
      const r = await api.post<{ message: string; data: StockDocument }>(`/erp/stock-documents/${doc.id}/${confirm}`, confirm === "reverse" ? { reason } : undefined);
      toast(r.message, undefined, "ok");
      setConfirm(null); setReason("");
      if (confirm === "reverse") router.push(`/erp/documents/${r.data.id}`);
      else load();
    } catch (e) {
      setActionError(e instanceof ApiError ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  if (error) return <ErrorState message={error} />;
  if (!doc) return <LoadingBlock rows={6} />;

  const draft = doc.status === "draft";
  const mayPrepare = can(PREPARE_PERMISSION[doc.type]);
  const costed = doc.type === "grn" || doc.type === "opening" || doc.type === "adjustment";
  const total = (doc.movements ?? []).reduce((s, m) => s + (m.type === "transfer_in" ? 0 : Number(m.value)), 0);
  const currency = config?.settings.base_currency ?? "TZS";

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/documents" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("erpDocuments")}</Link>}
        kicker={t(DOC_LABEL[doc.type])}
        title={<span className="erp-inline-icon tnum"><Icon name={DOCUMENT_ICON[doc.type]} size={34} /> {doc.number}</span>}
        subtitle={<>{doc.warehouse?.name}{doc.to_warehouse ? ` → ${doc.to_warehouse.name}` : ""}{doc.supplier ? ` · ${doc.supplier.name}` : ""} · {formatDate(doc.document_date, locale)}</>}
        actions={<>
          <DocStatus status={doc.status} />
          {draft && mayPrepare && <Link className="btn btn-secondary" href={`/erp/documents/${doc.id}/edit`}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</Link>}
          {draft && mayPrepare && <button className="btn btn-secondary" onClick={() => setConfirm("cancel")}>{t("erpCancelDraft")}</button>}
          {draft && can("inventory.post") && <button className="btn btn-primary" onClick={() => setConfirm("post")}><Icon name="ph-check-circle" size={18} /> {t("erpPost")}</button>}
          {doc.status === "posted" && !doc.reversal_of_id && can("inventory.reverse") && (
            <button className="btn btn-secondary" onClick={() => setConfirm("reverse")}><Icon name="ph-arrow-u-up-left" size={17} /> {t("erpReverse")}</button>
          )}
        </>}
      />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("erpLines")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead>
                <tr>
                  <th>{t("erpProduct")}</th>
                  {doc.type === "count" && <th className="num">{t("erpSystemQty")}</th>}
                  <th className="num">{doc.type === "count" ? t("erpCountedQty") : t("erpQuantity")}</th>
                  {doc.type === "count" && doc.status !== "draft" && <th className="num">{t("erpVariance")}</th>}
                  {costed && <th className="num">{t("erpUnitCost")}</th>}
                  <th>{t("erpBatch")}</th><th>{t("erpExpiry")}</th>
                </tr>
              </thead>
              <tbody>
                {doc.lines?.map((l) => (
                  <tr key={l.id}>
                    <td><Link href={`/erp/products/${l.product_id}`} className="erp-cell-link"><span className="erp-cell-title">{l.product?.name}</span><span className="erp-cell-sub tnum">{l.product?.sku}{l.serial_number ? ` · ${l.serial_number}` : ""}</span></Link></td>
                    {doc.type === "count" && <td className="num">{l.system_quantity !== null ? qty(l.system_quantity) : "-"}</td>}
                    <td className="num">{doc.type === "adjustment" ? <SignedQty value={l.quantity} /> : qty(l.quantity)} <span className="erp-muted">{l.product?.unit?.code}</span></td>
                    {doc.type === "count" && doc.status !== "draft" && <td className="num">{l.system_quantity !== null ? <SignedQty value={Number(l.quantity) - Number(l.system_quantity)} /> : "-"}</td>}
                    {costed && <td className="num">{l.unit_cost !== null ? amount(l.unit_cost) : "-"}</td>}
                    <td className="tnum">{l.batch_number || "-"}</td>
                    <td className="tnum">{l.expiry_date ? formatDate(l.expiry_date, locale) : "-"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </GlassCard>

        <GlassCard title={t("erpStatus")}>
          <dl className="erp-review">
            <dt>{t("erpPrepared")}</dt><dd>{doc.creator?.name ?? "-"} · {formatDateTime(doc.created_at, locale)}</dd>
            {doc.posted_at && <><dt>{t("erpPostedBy")}</dt><dd>{doc.poster?.name ?? "-"} · {formatDateTime(doc.posted_at, locale)}</dd></>}
            {doc.reversal_of && <><dt>{t("erpReversalOf")}</dt><dd><Link href={`/erp/documents/${doc.reversal_of.id}`} className="tnum">{doc.reversal_of.number}</Link></dd></>}
            {doc.reference && <><dt>{t("erpReference")}</dt><dd>{doc.reference}</dd></>}
            {doc.reason && <><dt>{t("erpReason")}</dt><dd>{doc.reason}</dd></>}
            {doc.movements && doc.movements.length > 0 && doc.type !== "transfer" && <><dt>{t("erpValue")}</dt><dd className="tnum">{currency} {amount(Math.abs(total))}</dd></>}
          </dl>
        </GlassCard>

        {doc.movements && doc.movements.length > 0 && (
          <GlassCard className="erp-span-3" title={t("erpMovementsPosted")} pad={false}>
            <MovementTable rows={doc.movements.map((m) => ({ ...m, product: doc.lines?.find((l) => l.product_id === m.product_id)?.product }))} showProduct />
          </GlassCard>
        )}
      </div>

      <Dialog
        open={confirm !== null}
        onClose={() => { setConfirm(null); setActionError(null); }}
        busy={busy}
        icon={confirm === "post" ? "ph-check-circle" : confirm === "reverse" ? "ph-arrow-u-up-left" : "ph-x-circle"}
        tone={confirm === "post" ? "info" : "warn"}
        title={confirm === "post" ? fill(t("erpPostQ"), { number: doc.number }) : confirm === "reverse" ? fill(t("erpReverseQ"), { number: doc.number }) : t("erpCancelDraft")}
        sub={confirm === "post" ? t("erpPostSub") : confirm === "reverse" ? t("erpReverseSub") : undefined}
        summary={[
          { label: t("erpType"), value: t(DOC_LABEL[doc.type]) },
          { label: t("erpWarehouse"), value: `${doc.warehouse?.name}${doc.to_warehouse ? ` → ${doc.to_warehouse.name}` : ""}` },
          { label: t("erpLines"), value: String(doc.lines?.length ?? 0) },
        ]}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setConfirm(null)} disabled={busy}>{t("erpBack")}</button>
          <button className={confirm === "post" ? "btn btn-primary" : "btn btn-danger"} onClick={act}
            disabled={busy || (confirm === "reverse" && reason.trim().length < 3)}>
            {confirm === "post" ? t("erpPost") : confirm === "reverse" ? t("erpReverse") : t("erpCancelDraft")}
          </button>
        </>}
      >
        {confirm === "reverse" && (
          <Field label={t("erpReason")} htmlFor="rev-reason" required>
            <input id="rev-reason" className="input" value={reason} onChange={(e) => setReason(e.target.value)} autoFocus />
          </Field>
        )}
        {actionError && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {actionError}</div>}
      </Dialog>
    </div>
  );
}

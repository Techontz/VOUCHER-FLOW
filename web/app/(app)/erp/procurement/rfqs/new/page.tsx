"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useQueryValue } from "@/lib/erp";
import { type Requisition, type Rfq, useLookups } from "@/lib/procurement-api";
import { ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Check, ErpGate } from "@/components/erp-ui";
import { BackLink, blankLine, type EditLine, LineEditor, linePayload } from "@/components/procurement-ui";

export default function NewRfqPage() {
  return <ErpGate module="procurement" permission="procurement.quote"><NewRfqLoader /></ErpGate>;
}

function NewRfqLoader() {
  const requisitionId = useQueryValue("requisition");
  const [requisition, setRequisition] = useState<Requisition | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (requisitionId) api.get<{ data: Requisition }>(`/erp/procurement/requisitions/${requisitionId}`).then((r) => setRequisition(r.data)).catch((e) => setError(e.message));
  }, [requisitionId]);

  if (error) return <ErrorState message={error} />;
  if (requisitionId === undefined || (requisitionId && !requisition)) return <LoadingBlock rows={5} />;
  return <NewRfq requisition={requisition} />;
}

function NewRfq({ requisition }: { requisition: Requisition | null }) {
  const { t, toast } = useApp();
  const router = useRouter();
  const { lookups, error } = useLookups();
  const [title, setTitle] = useState(requisition ? requisition.justification.slice(0, 160) : "");
  const [closing, setClosing] = useState("");
  const [notes, setNotes] = useState("");
  const [suppliers, setSuppliers] = useState<number[]>([]);
  const [lines, setLines] = useState<EditLine[]>(requisition?.lines?.map((l) => ({
    line_type: l.line_type, product_id: l.product_id ? String(l.product_id) : "", description: l.description,
    quantity: String(Number(l.quantity)), price: "", vat_rate: "", expense_account_id: l.expense_account_id ? String(l.expense_account_id) : "",
    purchase_requisition_line_id: l.id,
  })) ?? [blankLine()]);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  async function save() {
    setBusy(true); setFormError(null);
    try {
      const r = await api.post<{ data: Rfq }>("/erp/procurement/rfqs", {
        purchase_requisition_id: requisition?.id ?? null, title, closing_date: closing || null, notes: notes || null,
        supplier_ids: suppliers,
        lines: lines.map((l) => {
          const p = linePayload(l, "unit_price", false);
          return { line_type: p.line_type, product_id: p.product_id, description: p.description, quantity: p.quantity, expense_account_id: p.expense_account_id, purchase_requisition_line_id: p.purchase_requisition_line_id };
        }),
      });
      toast(t("erpSaved"), r.data.number, "ok");
      router.push(`/erp/procurement/rfqs/${r.data.id}`);
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  if (error) return <ErrorState message={error} />;
  if (!lookups) return <LoadingBlock rows={5} />;

  return (
    <div className="erp-page">
      <PageHeader back={<BackLink href="/erp/procurement/rfqs" label={t("prcRfqs")} />} kicker={requisition?.number}
        title={t("prcNewRfq")} subtitle={t("prcRfqFormSub")} />

      <GlassCard>
        <div className="erp-form-grid">
          <Field label={t("prcTitle")} htmlFor="rfq-title" required error={formError?.field("title")}>
            <input id="rfq-title" className="input" value={title} onChange={(e) => setTitle(e.target.value)} />
          </Field>
          <Field label={t("prcClosingDate")} htmlFor="rfq-close" error={formError?.field("closing_date")}>
            <input id="rfq-close" className="input" type="date" value={closing} onChange={(e) => setClosing(e.target.value)} />
          </Field>
        </div>
        <Field label={t("erpNotes")} htmlFor="rfq-notes" hint={t("erpOptional")}>
          <textarea id="rfq-notes" className="input" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
        </Field>
      </GlassCard>

      <GlassCard title={t("prcInviteSuppliers")} subtitle={t("prcInviteSuppliersSub")}>
        <div className="erp-checks">
          {lookups.suppliers.map((s) => (
            <Check key={s.id} label={s.name} hint={s.code} checked={suppliers.includes(s.id)}
              onChange={(v) => setSuppliers((all) => (v ? [...all, s.id] : all.filter((x) => x !== s.id)))} />
          ))}
        </div>
        {formError?.field("supplier_ids") && <div className="field-error">{formError.field("supplier_ids")}</div>}
      </GlassCard>

      <GlassCard title={t("erpLines")} pad={false}>
        <LineEditor lines={lines} onChange={setLines} lookups={lookups} priceLabel={t("prcEstimatedPrice")} error={formError} noPrice />
      </GlassCard>

      {formError && <div className="vf-alert tone-bad" role="alert"><Icon name="ph-warning-circle" size={20} /><span className="vf-alert-text">{formError.message}</span></div>}

      <div className="erp-stepnav">
        <button type="button" className="btn btn-secondary" onClick={() => router.back()}>{t("erpCancel")}</button>
        <button type="button" className="btn btn-primary" disabled={busy || !title.trim() || suppliers.length === 0} onClick={save}>
          <Icon name="ph-floppy-disk" size={18} /> {t("erpSaveDraft")}
        </button>
      </div>
    </div>
  );
}

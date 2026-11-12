"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useLookups, type Requisition } from "@/lib/procurement-api";
import { ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { BackLink, blankLine, type EditLine, LineEditor, linePayload } from "@/components/procurement-ui";

/** Raises or edits a draft requisition. Saving leaves a draft; submitting is a separate act. */
export function RequisitionForm({ existing }: { existing?: Requisition }) {
  const { t, toast, user } = useApp();
  const router = useRouter();
  const { lookups, error } = useLookups();
  const [departmentId, setDepartmentId] = useState(existing?.department_id ? String(existing.department_id) : user?.department_id ? String(user.department_id) : "");
  const [neededBy, setNeededBy] = useState(existing?.needed_by?.slice(0, 10) ?? "");
  const [justification, setJustification] = useState(existing?.justification ?? "");
  const [lines, setLines] = useState<EditLine[]>(existing?.lines?.map((l) => ({
    line_type: l.line_type, product_id: l.product_id ? String(l.product_id) : "", description: l.description,
    quantity: String(Number(l.quantity)), price: String(Number(l.estimated_unit_price)), vat_rate: "",
    expense_account_id: l.expense_account_id ? String(l.expense_account_id) : "",
  })) ?? [blankLine()]);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  async function save() {
    setBusy(true); setFormError(null);
    const payload = {
      department_id: departmentId ? Number(departmentId) : null, needed_by: neededBy || null, justification,
      lines: lines.map((l) => linePayload(l, "estimated_unit_price", false)),
    };
    try {
      const r = existing
        ? await api.put<{ data: Requisition }>(`/erp/procurement/requisitions/${existing.id}`, payload)
        : await api.post<{ data: Requisition }>("/erp/procurement/requisitions", payload);
      toast(t("erpSaved"), r.data.number, "ok");
      router.push(`/erp/procurement/requisitions/${r.data.id}`);
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
      <PageHeader back={<BackLink href={existing ? `/erp/procurement/requisitions/${existing.id}` : "/erp/procurement/requisitions"} label={t("prcRequisitions")} />}
        kicker={existing?.number} title={existing ? t("prcEditRequisition") : t("prcNewRequisition")} subtitle={t("prcRequisitionFormSub")} />

      <GlassCard>
        <div className="erp-form-grid">
          <Field label={t("prcDepartment")} htmlFor="rq-dep" error={formError?.field("department_id")}>
            <select id="rq-dep" className="input" value={departmentId} onChange={(e) => setDepartmentId(e.target.value)}>
              <option value="">-</option>
              {lookups.departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
            </select>
          </Field>
          <Field label={t("prcNeededBy")} htmlFor="rq-need" error={formError?.field("needed_by")}>
            <input id="rq-need" className="input" type="date" value={neededBy} onChange={(e) => setNeededBy(e.target.value)} />
          </Field>
        </div>
        <Field label={t("prcJustification")} htmlFor="rq-why" required error={formError?.field("justification")}>
          <textarea id="rq-why" className="input" rows={3} value={justification} onChange={(e) => setJustification(e.target.value)} />
        </Field>
      </GlassCard>

      <GlassCard title={t("erpLines")} subtitle={t("prcServiceLineHint")} pad={false}>
        <LineEditor lines={lines} onChange={setLines} lookups={lookups} priceLabel={t("prcEstimatedPrice")} error={formError} />
      </GlassCard>

      {formError && <div className="vf-alert tone-bad" role="alert"><Icon name="ph-warning-circle" size={20} /><span className="vf-alert-text">{formError.message}</span></div>}

      <div className="erp-stepnav">
        <button type="button" className="btn btn-secondary" onClick={() => router.back()}>{t("erpCancel")}</button>
        <button type="button" className="btn btn-primary" disabled={busy || justification.trim().length < 5} onClick={save}>
          <Icon name="ph-floppy-disk" size={18} /> {t("erpSaveDraft")}
        </button>
      </div>
    </div>
  );
}

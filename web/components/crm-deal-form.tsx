"use client";

import { useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, type Party, useErp } from "@/lib/erp";
import { OPEN_STAGES, type Opportunity, STAGE_LABEL } from "@/lib/crm-types";
import { Dialog, Field } from "@/components/ui";
import { usePeople } from "@/components/crm-ui";

/**
 * Creates an opportunity, or edits the details of one (its stage moves on the
 * board). Mount it only while open, so each opening starts from the deal as it is.
 */
export function DealDialog({ deal, onClose, onSaved }: {
  deal?: Opportunity | null; onClose: () => void; onSaved: (deal: Opportunity) => void;
}) {
  const { t, toast } = useApp();
  const { can } = useErp();
  const people = usePeople();
  const [customers, setCustomers] = useState<Party[]>([]);
  const [form, setForm] = useState(() => deal ? {
    title: deal.title, customer_id: String(deal.customer_id ?? ""), stage: deal.stage as string, value: String(Number(deal.value)),
    probability: String(deal.probability), expected_close_date: deal.expected_close_date?.slice(0, 10) ?? "", notes: deal.notes ?? "", owner_id: String(deal.owner_id ?? ""),
  } : { title: "", customer_id: "", stage: "prospecting", value: "", probability: "", expected_close_date: "", notes: "", owner_id: "" });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  useEffect(() => {
    if (can("customers.view")) {
      api.get<Paginated<Party>>("/erp/customers", { per_page: 200, active_only: 1 }).then((r) => setCustomers(r.data)).catch(() => undefined);
    }
  }, [can]);

  async function save() {
    setBusy(true); setError(null);
    const payload = {
      title: form.title, customer_id: form.customer_id ? Number(form.customer_id) : null, value: Number(form.value || 0),
      expected_close_date: form.expected_close_date || null, notes: form.notes || null,
      ...(form.probability !== "" ? { probability: Number(form.probability) } : {}),
      ...(form.owner_id ? { owner_id: Number(form.owner_id) } : {}),
      ...(deal ? {} : { stage: form.stage }),
    };
    try {
      const r = deal
        ? await api.put<{ data: Opportunity }>(`/erp/crm/opportunities/${deal.id}`, payload)
        : await api.post<{ data: Opportunity }>("/erp/crm/opportunities", payload);
      toast(t("erpSaved"), r.data.number, "ok");
      onSaved(r.data);
    } catch (e) { setError(e instanceof ApiError ? e : new ApiError(0, String(e))); } finally { setBusy(false); }
  }

  const set = (k: keyof typeof form, v: string) => setForm((f) => ({ ...f, [k]: v }));

  return (
    <Dialog open wide title={deal ? deal.number : t("crmNewOpportunity")} onClose={onClose} busy={busy}
      actions={<>
        <button className="btn btn-secondary" onClick={onClose} disabled={busy}>{t("erpCancel")}</button>
        <button className="btn btn-primary" onClick={save} disabled={busy || !form.title.trim()}>{t("erpSave")}</button>
      </>}>
      {error && !Object.keys(error.errors).length && <div className="field-error" role="alert">{error.message}</div>}
      <Field label={t("crmTitleField")} htmlFor="op-title" required error={error?.field("title")}>
        <input id="op-title" className="input" value={form.title} onChange={(e) => set("title", e.target.value)} />
      </Field>
      <div className="erp-form-grid">
        {can("customers.view") && (
          <Field label={t("crmCustomer")} htmlFor="op-customer" error={error?.field("customer_id")}>
            <select id="op-customer" className="input" value={form.customer_id} onChange={(e) => set("customer_id", e.target.value)}>
              <option value="">{t("crmNone")}</option>
              {customers.map((c) => <option key={c.id} value={c.id}>{c.name} ({c.code})</option>)}
            </select>
          </Field>
        )}
        {!deal && (
          <Field label={t("crmStage")} htmlFor="op-stage" error={error?.field("stage")}>
            <select id="op-stage" className="input" value={form.stage} onChange={(e) => set("stage", e.target.value)}>
              {OPEN_STAGES.map((s) => <option key={s} value={s}>{t(STAGE_LABEL[s])}</option>)}
            </select>
          </Field>
        )}
        <Field label={t("crmValue")} htmlFor="op-value" required error={error?.field("value")}>
          <input id="op-value" className="input" type="number" min={0} value={form.value} onChange={(e) => set("value", e.target.value)} />
        </Field>
        <Field label={t("crmProbability")} htmlFor="op-prob" error={error?.field("probability")}>
          <input id="op-prob" className="input" type="number" min={0} max={100} value={form.probability} onChange={(e) => set("probability", e.target.value)} />
        </Field>
        <Field label={t("crmCloseDate")} htmlFor="op-date" error={error?.field("expected_close_date")}>
          <input id="op-date" className="input" type="date" value={form.expected_close_date} onChange={(e) => set("expected_close_date", e.target.value)} />
        </Field>
        {can("crm.assign") && !deal && (
          <Field label={t("crmOwner")} htmlFor="op-owner" error={error?.field("owner_id")}>
            <select id="op-owner" className="input" value={form.owner_id} onChange={(e) => set("owner_id", e.target.value)}>
              <option value="">{t("crmMe")}</option>
              {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </Field>
        )}
      </div>
      <Field label={t("crmNotes")} htmlFor="op-notes" error={error?.field("notes")}>
        <textarea id="op-notes" className="input" rows={3} value={form.notes} onChange={(e) => set("notes", e.target.value)} />
      </Field>
    </Dialog>
  );
}

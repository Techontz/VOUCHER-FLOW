"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, qty, useErp, useQueryValue } from "@/lib/erp";
import { addDays, type Bom, type ProductionOrder, type Requirement, type StandardCost, today, useProductionOptions } from "@/lib/production-api";
import { Badge, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";
import { RequirementTable } from "@/components/production-requirements";

export default function NewProductionOrderPage() {
  return <ErpGate module="production" permission="production.plan"><NewOrder /></ErpGate>;
}

interface Check { bom: Pick<Bom, "id" | "version" | "name" | "output_quantity">; standard: StandardCost; requirements: Requirement[] }

/**
 * Plans an order. As soon as a product, quantity and materials store are
 * chosen, the requirement check shows what the bill of materials needs of
 * each component against what the store holds, before anything is saved.
 */
function NewOrder() {
  const { t, toast } = useApp();
  const { config } = useErp();
  const router = useRouter();
  const preset = useQueryValue("product");
  const { options, error } = useProductionOptions();
  const [chosenProduct, setProductId] = useState("");
  const [boms, setBoms] = useState<Bom[]>([]);
  const [bomId, setBomId] = useState("");
  const [quantity, setQuantity] = useState("");
  const [chosenMaterials, setMaterialsId] = useState("");
  const [chosenOutput, setOutputId] = useState("");
  const [start, setStart] = useState(today());
  const [end, setEnd] = useState(addDays(today(), 1));
  const [reference, setReference] = useState("");
  const [notes, setNotes] = useState("");
  const [check, setCheck] = useState<Check | null>(null);
  const [checkError, setCheckError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<ApiError | null>(null);

  // Until someone chooses, the main store supplies and the finished goods warehouse receives.
  const store = options?.warehouses.find((w) => w.code === "MAIN") ?? options?.warehouses[0];
  const finishedStore = options?.warehouses.find((w) => w.code === "FGW") ?? store;
  const productId = chosenProduct || preset || "";
  const materialsId = chosenMaterials || (store ? String(store.id) : "");
  const outputId = chosenOutput || (finishedStore ? String(finishedStore.id) : "");

  useEffect(() => {
    if (!productId) return;
    api.get<Paginated<Bom>>("/erp/production/boms", { product_id: productId, per_page: 50 })
      .then((r) => { setBoms(r.data); setBomId(String(r.data.find((b) => b.is_active)?.id ?? "")); })
      .catch(() => setBoms([]));
  }, [productId]);

  useEffect(() => {
    if (!productId || !materialsId || !(Number(quantity) > 0)) return;
    const id = window.setTimeout(() => {
      api.post<{ data: Check }>("/erp/production/orders/check", {
        product_id: Number(productId), bom_id: bomId ? Number(bomId) : null,
        planned_quantity: Number(quantity), materials_warehouse_id: Number(materialsId),
      }).then((r) => { setCheck(r.data); setCheckError(null); })
        .catch((e) => { setCheck(null); setCheckError(e.message); });
    }, 300);
    return () => window.clearTimeout(id);
  }, [productId, bomId, quantity, materialsId]);

  async function save() {
    setBusy(true); setFormError(null);
    try {
      const r = await api.post<{ message: string; data: ProductionOrder }>("/erp/production/orders", {
        product_id: Number(productId), bom_id: bomId ? Number(bomId) : null, planned_quantity: Number(quantity),
        materials_warehouse_id: Number(materialsId), output_warehouse_id: Number(outputId),
        planned_start: start, planned_end: end, reference: reference || null, notes: notes || null,
      });
      toast(r.message, undefined, "ok");
      router.push(`/erp/production/orders/${r.data.id}`);
    } catch (e) {
      setFormError(e instanceof ApiError ? e : new ApiError(0, String(e)));
    } finally {
      setBusy(false);
    }
  }

  if (error) return <ErrorState message={error} />;
  if (!options) return <LoadingBlock rows={5} />;

  const currency = config?.settings.base_currency ?? "TZS";
  const product = options.finished.find((p) => String(p.id) === productId);
  const short = check?.requirements.filter((r) => !r.sufficient) ?? [];

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/production/orders" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("prdNavOrders")}</Link>}
        title={t("prdNewOrder")} subtitle={t("prdNewOrderSub")} />

      <GlassCard>
        <div className="erp-form-grid">
          <Field label={t("erpProduct")} htmlFor="o-product" required error={formError?.field("product_id")}>
            <select id="o-product" className="input" value={productId} onChange={(e) => { setProductId(e.target.value); setCheck(null); setBoms([]); setBomId(""); }}>
              <option value="">{t("erpPickProduct")}</option>
              {options.finished.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.sku}</option>)}
            </select>
          </Field>
          <Field label={t("prdBomVersion")} htmlFor="o-bom" error={formError?.field("bom_id")}
            hint={productId && boms.length === 0 ? t("prdNoBomForProduct") : undefined}>
            <select id="o-bom" className="input" value={bomId} onChange={(e) => setBomId(e.target.value)} disabled={boms.length === 0}>
              {boms.map((b) => <option key={b.id} value={b.id}>{`${t("prdVersion")} ${b.version}${b.is_active ? ` (${t("prdActive")})` : ""} · ${b.name}`}</option>)}
            </select>
          </Field>
          <Field label={t("prdPlannedQty")} htmlFor="o-qty" required error={formError?.field("planned_quantity")} hint={product?.unit?.name}>
            <input id="o-qty" className="input tnum" type="number" min={0} step="any" value={quantity} onChange={(e) => setQuantity(e.target.value)} />
          </Field>
          <Field label={t("prdMaterialsFrom")} htmlFor="o-mat" required error={formError?.field("materials_warehouse_id")}>
            <select id="o-mat" className="input" value={materialsId} onChange={(e) => setMaterialsId(e.target.value)}>
              {options.warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </Field>
          <Field label={t("prdOutputTo")} htmlFor="o-out" required error={formError?.field("output_warehouse_id")}>
            <select id="o-out" className="input" value={outputId} onChange={(e) => setOutputId(e.target.value)}>
              {options.warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </Field>
          <Field label={t("prdPlannedStart")} htmlFor="o-start" required error={formError?.field("planned_start")}>
            <input id="o-start" className="input" type="date" value={start} onChange={(e) => { setStart(e.target.value); if (end < e.target.value) setEnd(e.target.value); }} />
          </Field>
          <Field label={t("prdPlannedEnd")} htmlFor="o-end" required error={formError?.field("planned_end")}>
            <input id="o-end" className="input" type="date" value={end} min={start} onChange={(e) => setEnd(e.target.value)} />
          </Field>
          <Field label={t("erpReference")} htmlFor="o-ref" hint={t("erpOptional")} error={formError?.field("reference")}>
            <input id="o-ref" className="input" value={reference} onChange={(e) => setReference(e.target.value)} />
          </Field>
        </div>
        <Field label={t("prdNotes")} htmlFor="o-notes" hint={t("erpOptional")} error={formError?.field("notes")}>
          <textarea id="o-notes" className="input" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
        </Field>
      </GlassCard>

      {checkError && productId && <div className="vf-alert tone-warn" role="status"><Icon name="ph-warning" size={20} /><span className="vf-alert-text">{checkError}</span></div>}

      {check && (
        <GlassCard title={t("prdRequirementCheck")}
          subtitle={fill(t("prdStandardCostLine"), { cost: `${currency} ${amount(check.standard.unit_cost)}`, total: `${currency} ${amount(check.standard.unit_cost * Number(quantity || 0))}` })}
          action={short.length === 0
            ? <Badge tone="ok" dot>{t("prdAllAvailable")}</Badge>
            : <Badge tone="warn" dot>{fill(t("prdShortCount"), { n: short.length })}</Badge>}
          pad={false}>
          <RequirementTable rows={check.requirements} planning />
          {short.length > 0 && <div className="erp-lines-foot"><span className="erp-muted">{t("prdShortHint")}</span></div>}
        </GlassCard>
      )}

      {formError && <div className="vf-alert tone-bad" role="alert"><Icon name="ph-warning-circle" size={20} /><span className="vf-alert-text">{formError.message}</span></div>}

      <div className="erp-stepnav">
        <Link className="btn btn-secondary" href="/erp/production/orders">{t("erpCancel")}</Link>
        <button type="button" className="btn btn-primary" onClick={save}
          disabled={busy || !productId || !bomId || !(Number(quantity) > 0) || !materialsId || !outputId}>
          <Icon name="ph-floppy-disk" size={18} /> {t("prdPlanOrder")}
        </button>
      </div>
      {product && quantity && <p className="erp-muted">{fill(t("prdPlanSummary"), { qty: qty(quantity), product: product.name })}</p>}
    </div>
  );
}

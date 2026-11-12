"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, qty, useErp } from "@/lib/erp";
import { formatDate, formatDateTime } from "@/lib/format";
import type { Bom } from "@/lib/production-api";
import { Badge, Dialog, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { ErpGate, fill } from "@/components/erp-ui";

export default function BomPage() {
  return <ErpGate module="production" permission="production.view"><BomDetail /></ErpGate>;
}

type Action = "version" | "activate" | "delete";

function BomDetail() {
  const { t, locale, toast } = useApp();
  const { can, config } = useErp();
  const router = useRouter();
  const { id } = useParams<{ id: string }>();
  const [bom, setBom] = useState<Bom | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<Action | null>(null);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const load = useCallback(() => {
    api.get<{ data: Bom }>(`/erp/production/boms/${id}`).then((r) => setBom(r.data)).catch((e) => setError(e.message));
  }, [id]);
  useEffect(load, [load]);

  async function act() {
    if (!bom || !confirm) return;
    setBusy(true); setActionError(null);
    try {
      if (confirm === "delete") {
        const r = await api.delete<{ message: string }>(`/erp/production/boms/${bom.id}`);
        toast(r.message, undefined, "ok");
        router.push("/erp/production/boms");
        return;
      }
      const path = confirm === "version" ? "versions" : "activate";
      const r = await api.post<{ message: string; data: Bom }>(`/erp/production/boms/${bom.id}/${path}`);
      toast(r.message, undefined, "ok");
      setConfirm(null);
      if (confirm === "version") router.push(`/erp/production/boms/${r.data.id}/edit`);
      else load();
    } catch (e) {
      setActionError(e instanceof ApiError ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  if (error) return <ErrorState message={error} />;
  if (!bom) return <LoadingBlock rows={6} />;

  const currency = config?.settings.base_currency ?? "TZS";
  const manage = can("production.manage");
  const used = (bom.orders_count ?? 0) > 0;
  const standard = bom.standard;

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/production/boms" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("prdNavBoms")}</Link>}
        kicker={`${t("prdVersion")} ${bom.version}`}
        title={bom.name}
        subtitle={<>{bom.product?.name} · {fill(t("prdPerBatchOf"), { qty: qty(bom.output_quantity), unit: bom.product?.unit?.code ?? "" })}</>}
        actions={<>
          {bom.is_active ? <Badge tone="ok" dot>{t("prdActive")}</Badge> : <Badge tone="neutral" dot>{t("prdInactive")}</Badge>}
          {manage && !used && <Link className="btn btn-secondary" href={`/erp/production/boms/${bom.id}/edit`}><Icon name="ph-pencil-simple" size={17} /> {t("erpEdit")}</Link>}
          {manage && <button className="btn btn-secondary" onClick={() => setConfirm("version")}><Icon name="ph-copy" size={17} /> {t("prdNewVersion")}</button>}
          {manage && !bom.is_active && <button className="btn btn-primary" onClick={() => setConfirm("activate")}><Icon name="ph-check-circle" size={17} /> {t("prdActivate")}</button>}
          {manage && !used && <button className="btn btn-secondary" onClick={() => setConfirm("delete")}><Icon name="ph-trash" size={17} /> {t("prdDelete")}</button>}
          {can("production.plan") && bom.is_active && <Link className="btn btn-primary" href={`/erp/production/orders/new?product=${bom.product_id}`}><Icon name="ph-factory" size={17} /> {t("prdNewOrder")}</Link>}
        </>}
      />

      <div className="erp-grid">
        <GlassCard className="erp-span-2" title={t("prdComponents")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("prdComponent")}</th><th className="num">{t("prdQtyPerBatch")}</th><th className="num">{t("prdScrapPercent")}</th><th className="num">{t("prdPerUnit")}</th><th className="num">{t("prdUnitCost")}</th><th className="num">{t("prdCostPerUnit")}</th></tr></thead>
              <tbody>
                {bom.lines?.map((l) => {
                  const s = standard?.lines.find((x) => x.product_id === l.product_id);
                  return (
                    <tr key={l.id}>
                      <td><span className="erp-cell-title">{l.product?.name}</span><span className="erp-cell-sub tnum">{l.product?.sku}{l.note ? ` · ${l.note}` : ""}</span></td>
                      <td className="num">{qty(l.quantity)} <span className="erp-muted">{l.product?.unit?.code}</span></td>
                      <td className="num">{qty(l.scrap_percent)}%</td>
                      <td className="num">{s ? qty(s.per_unit) : "-"}</td>
                      <td className="num">{s ? amount(s.unit_cost) : "-"}</td>
                      <td className="num">{s ? amount(Math.round(s.cost_per_unit * 100) / 100) : "-"}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </GlassCard>

        <GlassCard title={t("prdStandardCost")} subtitle={t("prdStandardCostSub")}>
          <dl className="erp-review">
            <dt>{t("prdMaterialsPerUnit")}</dt><dd className="tnum">{currency} {amount(Math.round((standard?.materials ?? 0) * 100) / 100)}</dd>
            <dt>{t("prdConversionPerUnit")}</dt><dd className="tnum">{currency} {amount(Math.round((standard?.conversion ?? 0) * 100) / 100)}</dd>
            <dt>{t("prdStandardUnit")}</dt><dd className="tnum"><strong>{currency} {amount(Math.round((standard?.unit_cost ?? 0) * 100) / 100)}</strong></dd>
            <dt>{t("prdLabourPerBatch")}</dt><dd className="tnum">{currency} {amount(bom.labour_cost)}</dd>
            <dt>{t("prdOverheadPerBatch")}</dt><dd className="tnum">{currency} {amount(bom.overhead_cost)}</dd>
            <dt>{t("prdWorkCentre")}</dt><dd>{bom.work_centre ? `${bom.work_centre.code} · ${bom.work_centre.name}` : "-"}</dd>
            <dt>{t("prdUsedBy")}</dt><dd className="tnum">{fill(t("prdOrdersCount"), { n: bom.orders_count ?? 0 })}</dd>
            <dt>{t("erpPrepared")}</dt><dd>{bom.creator?.name ?? "-"} · {formatDateTime(bom.created_at, locale)}</dd>
            {bom.notes && <><dt>{t("prdNotes")}</dt><dd>{bom.notes}</dd></>}
          </dl>
        </GlassCard>

        {bom.versions && bom.versions.length > 1 && (
          <GlassCard className="erp-span-3" title={t("prdVersions")} pad={false}>
            <ul className="erp-list">
              {bom.versions.map((v) => (
                <li key={v.id}>
                  <Link href={`/erp/production/boms/${v.id}`} className="erp-list-row" aria-current={v.id === bom.id ? "true" : undefined}>
                    <span className="erp-list-icon"><Icon name="ph-git-branch" size={18} /></span>
                    <span className="erp-list-main">
                      <span className="erp-list-title">{t("prdVersion")} {v.version} · {v.name}</span>
                      <span className="erp-list-sub">{formatDate(v.created_at, locale)}</span>
                    </span>
                    {v.is_active ? <Badge tone="ok" dot>{t("prdActive")}</Badge> : <Badge tone="neutral" dot>{t("prdInactive")}</Badge>}
                  </Link>
                </li>
              ))}
            </ul>
          </GlassCard>
        )}
      </div>

      <Dialog open={confirm !== null} onClose={() => { setConfirm(null); setActionError(null); }} busy={busy}
        icon={confirm === "delete" ? "ph-trash" : confirm === "activate" ? "ph-check-circle" : "ph-copy"}
        tone={confirm === "delete" ? "warn" : "info"}
        title={confirm === "delete" ? t("prdDeleteQ") : confirm === "activate" ? fill(t("prdActivateQ"), { version: bom.version }) : t("prdNewVersionQ")}
        sub={confirm === "activate" ? t("prdActivateSub") : confirm === "version" ? t("prdNewVersionSub") : undefined}
        actions={<>
          <button className="btn btn-secondary" onClick={() => setConfirm(null)} disabled={busy}>{t("erpBack")}</button>
          <button className={confirm === "delete" ? "btn btn-danger" : "btn btn-primary"} onClick={act} disabled={busy}>
            {confirm === "delete" ? t("prdDelete") : confirm === "activate" ? t("prdActivate") : t("prdNewVersion")}
          </button>
        </>}>
        {actionError && <div className="field-error" role="alert"><Icon name="ph-warning-circle" size={15} /> {actionError}</div>}
      </Dialog>
    </div>
  );
}

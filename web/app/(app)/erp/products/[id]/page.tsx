"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Product, qty, type StockBalance, type StockMovement, useErp } from "@/lib/erp";
import { formatDate } from "@/lib/format";
import { Badge, EmptyState, ErrorState, GlassCard, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { ErpGate, PRODUCT_TYPE_LABEL } from "@/components/erp-ui";
import { MovementTable } from "@/components/erp-movements";

interface Detail extends Product {
  on_hand: number; stock_value: number;
  balances: StockBalance[]; movements: StockMovement[];
}

export default function ProductPage() {
  return <ErpGate module="inventory" permission="inventory.view"><ProductDetail /></ErpGate>;
}

function ProductDetail() {
  const { t, locale } = useApp();
  const { config } = useErp();
  const { id } = useParams<{ id: string }>();
  const [p, setP] = useState<Detail | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Detail }>(`/erp/products/${id}`).then((r) => setP(r.data)).catch((e) => setError(e.message));
  }, [id]);

  if (error) return <ErrorState message={error} />;
  if (!p) return <LoadingBlock rows={6} />;

  const currency = config?.settings.base_currency ?? "TZS";
  const fields = config?.settings.product_fields ?? [];

  return (
    <div className="erp-page">
      <PageHeader
        back={<Link href="/erp/products" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("erpProducts")}</Link>}
        title={p.name}
        subtitle={<span className="tnum">{p.sku}{p.barcode ? ` · ${p.barcode}` : ""} · {t(PRODUCT_TYPE_LABEL[p.type])}{p.category ? ` · ${p.category.name}` : ""}</span>}
        actions={!p.is_active ? <Badge>{t("erpInactive")}</Badge> : undefined}
      />

      <StatPills items={[
        { label: t("erpOnHand"), value: `${qty(p.on_hand)} ${p.unit?.code ?? ""}`, tone: Number(p.reorder_level) > 0 && p.on_hand <= Number(p.reorder_level) ? "warn" : "neutral" },
        { label: t("erpStockValue"), value: `${currency} ${amount(p.stock_value)}` },
        { label: t("erpCostPrice"), value: amount(p.cost_price) },
        { label: t("erpSalePrice"), value: amount(p.sale_price) },
        { label: t("erpReorderLevel"), value: qty(p.reorder_level) },
      ]} />

      <div className="erp-grid">
        <GlassCard title={t("erpWhereHeld")} pad={false}>
          {p.balances.length === 0 ? <EmptyState icon="ph-package" title={t("erpNoMovements")} /> : (
            <div className="vf-table-wrap">
              <table className="table vf-table">
                <thead><tr><th>{t("erpWarehouse")}</th><th>{t("erpBatch")}</th><th>{t("erpExpiry")}</th><th className="num">{t("erpOnHand")}</th><th className="num">{t("erpAvgCost")}</th></tr></thead>
                <tbody>
                  {p.balances.map((b) => (
                    <tr key={b.id}>
                      <td>{b.warehouse?.name}</td>
                      <td className="tnum">{b.batch_number || "-"}</td>
                      <td className="tnum">{b.expiry_date ? formatDate(b.expiry_date, locale) : "-"}</td>
                      <td className="num">{qty(b.quantity)}</td>
                      <td className="num">{amount(b.average_cost)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </GlassCard>

        <GlassCard title={t("erpTracking")}>
          <dl className="erp-review">
            <dt>{t("erpUnit")}</dt><dd>{p.unit?.name} ({p.unit?.code})</dd>
            {p.brand && <><dt>{t("erpBrand")}</dt><dd>{p.brand}</dd></>}
            <dt>{t("erpTracking")}</dt>
            <dd className="erp-flags">
              {p.track_batches && <Badge tone="info">{t("erpTrackBatches")}</Badge>}
              {p.track_expiry && <Badge tone="info">{t("erpTrackExpiry")}</Badge>}
              {p.track_serials && <Badge tone="info">{t("erpTrackSerials")}</Badge>}
              {!p.track_batches && !p.track_expiry && !p.track_serials && "-"}
            </dd>
            {fields.filter((f) => p.custom_fields?.[f.key] !== undefined).map((f) => (
              <span key={f.key} style={{ display: "contents" }}>
                <dt>{f.label}</dt>
                <dd>{typeof p.custom_fields?.[f.key] === "boolean" ? (p.custom_fields?.[f.key] ? "✓" : "-") : String(p.custom_fields?.[f.key])}</dd>
              </span>
            ))}
          </dl>
        </GlassCard>

        <GlassCard className="erp-span-2" title={t("erpLedger")} subtitle={t("erpMovementsPosted")} pad={false}>
          {p.movements.length === 0 ? <EmptyState icon="ph-list" title={t("erpNoMovements")} /> : <MovementTable rows={p.movements} />}
        </GlassCard>
      </div>
    </div>
  );
}

"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { amount, type Paginated, qty, useErp } from "@/lib/erp";
import type { Bom } from "@/lib/production-api";
import { Badge, EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";

export default function BomsPage() {
  return <ErpGate module="production" permission="production.view"><Boms /></ErpGate>;
}

function Boms() {
  const { t } = useApp();
  const { can, config } = useErp();
  const [q, setQ] = useState("");
  const [active, setActive] = useState<"" | "1" | "0">("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<Bom> | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const id = window.setTimeout(() => {
      api.get<Paginated<Bom>>("/erp/production/boms", { q: q || undefined, active: active || undefined, page })
        .then(setRows).catch((e) => setError(e.message));
    }, q ? 220 : 0);
    return () => window.clearTimeout(id);
  }, [q, active, page]);

  const currency = config?.settings.base_currency ?? "TZS";

  return (
    <div className="erp-page">
      <PageHeader title={t("prdNavBoms")} subtitle={t("prdBomsSub")}
        actions={can("production.manage") && <>
          <Link className="btn btn-secondary" href="/erp/production/work-centres"><Icon name="ph-gear-six" size={18} /> {t("prdNavCentres")}</Link>
          <Link className="btn btn-primary" href="/erp/production/boms/new"><Icon name="ph-plus" size={18} /> {t("prdNewBom")}</Link>
        </>} />

      <Toolbar>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={t("prdSearchBoms")} />
        <FilterChips<"" | "1" | "0"> value={active} onChange={(v) => { setActive(v); setPage(1); }} items={[
          { value: "", label: t("erpAll") }, { value: "1", label: t("prdActive") }, { value: "0", label: t("prdInactive") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} /> : !rows ? <LoadingBlock /> : rows.data.length === 0 ? (
        <EmptyState icon="ph-list-checks" title={t("prdNoBoms")}
          action={can("production.manage") ? <Link className="btn btn-primary" href="/erp/production/boms/new">{t("prdNewBom")}</Link> : undefined} />
      ) : (
        <>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("prdBomName")}</th><th>{t("prdFinishedProduct")}</th><th className="num">{t("prdOutputQty")}</th><th className="num">{t("prdComponents")}</th><th className="num">{t("prdStandardUnit")}</th><th>{t("prdWorkCentre")}</th><th>{t("erpStatus")}</th></tr></thead>
              <tbody>
                {rows.data.map((b) => (
                  <tr key={b.id} className="is-clickable">
                    <td><Link href={`/erp/production/boms/${b.id}`} className="erp-cell-link"><span className="erp-cell-title">{b.name}</span><span className="erp-cell-sub">{t("prdVersion")} {b.version}</span></Link></td>
                    <td>{b.product?.name}<span className="erp-cell-sub tnum">{b.product?.sku}</span></td>
                    <td className="num">{qty(b.output_quantity)} <span className="erp-muted">{b.product?.unit?.code}</span></td>
                    <td className="num">{b.lines_count}</td>
                    <td className="num">{currency} {amount(b.standard_cost ?? 0)}</td>
                    <td>{b.work_centre ? b.work_centre.code : "-"}</td>
                    <td>{b.is_active ? <Badge tone="ok" dot>{t("prdActive")}</Badge> : <Badge tone="neutral" dot>{t("prdInactive")}</Badge>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}
    </div>
  );
}

"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate } from "@/lib/format";
import { DOC_TYPE_LABEL, type DocumentRow } from "@/lib/crm-types";
import { Badge, EmptyState, ErrorState, Icon, LoadingBlock, PageHeader, StatPills } from "@/components/ui";
import { Toolbar } from "@/components/app-ui";
import { ErpGate, fill, FilterChips } from "@/components/erp-ui";

export default function ExpiringPage() {
  return <ErpGate module="documents" permission="documents.view"><Expiring /></ErpGate>;
}

/** Licences, permits, certificates and policies about to lapse, soonest first, with the lapsed ones on top. */
function Expiring() {
  const { t, locale } = useApp();
  const router = useRouter();
  const [days, setDays] = useState<"30" | "60" | "90">("30");
  const [rows, setRows] = useState<DocumentRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    api.get<{ data: DocumentRow[] }>("/erp/files/expiring", { days }).then((r) => setRows(r.data)).catch((e) => setError(e.message));
  }, [days]);
  useEffect(load, [load]);

  const expired = rows?.filter((r) => (r.days_left ?? 0) < 0).length ?? 0;
  const week = rows?.filter((r) => (r.days_left ?? 0) >= 0 && (r.days_left ?? 0) <= 7).length ?? 0;

  return (
    <div className="erp-page">
      <PageHeader title={t("docExpiring")} subtitle={t("docExpiringSub")}
        back={<Link href="/erp/files" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("docTitle")}</Link>} />

      {rows && (
        <StatPills label={t("docExpiring")} items={[
          { label: t("docExpired"), value: expired, tone: expired ? "bad" : "neutral", icon: "ph-warning-octagon" },
          { label: fill(t("docWithinDays"), { n: 7 }), value: week, tone: week ? "warn" : "neutral", icon: "ph-hourglass-high" },
          { label: fill(t("docWithinDays"), { n: days }), value: rows.length - expired, icon: "ph-hourglass-medium" },
        ]} />
      )}

      <Toolbar>
        <FilterChips<"30" | "60" | "90"> value={days} onChange={setDays} items={(["30", "60", "90"] as const).map((d) => ({ value: d, label: fill(t("docWithinDays"), { n: d }) }))} />
      </Toolbar>

      {error ? <ErrorState message={error} onRetry={load} /> : !rows ? <LoadingBlock /> : rows.length === 0 ? <EmptyState icon="ph-check-circle" tone="ok" title={t("docNothingExpiring")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("docTitleField")}</th><th>{t("docType")}</th><th>{t("docFolder")}</th><th>{t("docExpires")}</th><th /></tr></thead>
            <tbody>
              {rows.map((d) => {
                const left = d.days_left ?? 0;
                return (
                  <tr key={d.id} className="is-clickable" onClick={() => router.push(`/erp/files/${d.id}`)}>
                    <td><Link href={`/erp/files/${d.id}`} className="erp-cell-link" onClick={(e) => e.stopPropagation()}><span className="erp-cell-title">{d.title}</span>{d.reference && <span className="erp-cell-sub">{d.reference}</span>}</Link></td>
                    <td>{t(DOC_TYPE_LABEL[d.document_type] ?? "docTypeOther")}</td>
                    <td>{d.folder?.name ?? "-"}</td>
                    <td className="tnum">{d.expires_on ? formatDate(d.expires_on, locale) : "-"}</td>
                    <td>
                      <Badge tone={left < 0 ? "bad" : left <= 7 ? "warn" : "info"} dot>
                        {left < 0 ? fill(t("docExpiredAgo"), { n: -left }) : left === 0 ? t("docExpiresToday") : fill(t("docDaysLeft"), { n: left })}
                      </Badge>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

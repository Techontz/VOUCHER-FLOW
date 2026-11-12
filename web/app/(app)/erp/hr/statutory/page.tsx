"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { useErp } from "@/lib/erp";
import { monthLabel } from "@/lib/hr";
import { formatDate } from "@/lib/format";
import { EmptyState, ErrorState, Field, GlassCard, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Toolbar } from "@/components/app-ui";
import { FormDialog, HrGate, HrStatus, payload, Tzs } from "@/components/hr-ui";

interface Row { run_id: number; number: string; period: string; status: string; employees: number; gross: number; paye: number; nssf_employee: number; nssf_employer: number; nssf_total: number; wcf: number; sdl: number; heslb: number }
interface Rate { id?: number; code: string; name: string; kind: string; base: string; party: string; rate: number | string | null; bands: { from: number; to: number | null; base: number; rate: number }[] | null; effective_from: string }
const COLS = ["gross", "paye", "nssf_employee", "nssf_employer", "nssf_total", "wcf", "sdl", "heslb"] as const;

export default function StatutoryPage() {
  return <HrGate anyOf={["hr.payroll.prepare", "hr.payroll.authorise", "hr.payroll.post"]}><Statutory /></HrGate>;
}

function Statutory() {
  const { t, locale, toast } = useApp();
  const { can } = useErp();
  const [year, setYear] = useState(new Date().getFullYear());
  const [data, setData] = useState<{ data: Row[]; totals: Record<string, number> } | null>(null);
  const [rates, setRates] = useState<{ data: Rate[]; in_force: Record<string, Rate> } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [newRate, setNewRate] = useState<Rate | null>(null);

  const load = useCallback(() => {
    api.get<NonNullable<typeof data>>("/erp/hr/statutory-returns", { year }).then(setData).catch((e) => setError(e.message));
    api.get<NonNullable<typeof rates>>("/erp/hr/statutory-rates").then(setRates).catch(() => undefined);
  }, [year]);
  useEffect(load, [load]);

  const label: Record<(typeof COLS)[number], string> = {
    gross: t("hrGross"), paye: t("hrPaye"), nssf_employee: t("hrNssfEmployee"), nssf_employer: t("hrNssfEmployer"), nssf_total: t("hrNssfTotal"), wcf: t("hrWcf"), sdl: t("hrSdl"), heslb: t("hrHeslb"),
  };

  return (
    <div className="erp-page">
      <PageHeader back={<Link href="/erp/hr/payroll" className="erp-back"><Icon name="ph-arrow-left" size={16} /> {t("hrPayroll")}</Link>}
        title={t("hrStatutory")} subtitle={t("hrStatutorySub")} />
      <Toolbar><Field label={t("hrYear")} htmlFor="st-year"><input id="st-year" className="input" type="number" value={year} onChange={(e) => setYear(Number(e.target.value))} style={{ maxWidth: 120 }} /></Field></Toolbar>

      {error ? <ErrorState message={error} /> : !data ? <LoadingBlock /> : data.data.length === 0 ? <EmptyState icon="ph-bank" title={t("hrNoReturns")} /> : (
        <div className="vf-table-wrap">
          <table className="table vf-table">
            <thead><tr><th>{t("hrPeriod")}</th>{COLS.map((c) => <th key={c} className="num">{label[c]}</th>)}<th>{t("erpStatus")}</th></tr></thead>
            <tbody>
              {data.data.map((r) => (
                <tr key={r.run_id}>
                  <td><Link className="erp-cell-link" href={`/erp/hr/payroll/${r.run_id}`}><span className="erp-cell-title">{monthLabel(r.period, locale)}</span><span className="erp-cell-sub tnum">{r.number} · {r.employees}</span></Link></td>
                  {COLS.map((c) => <td key={c} className="num"><Tzs value={r[c]} /></td>)}
                  <td><HrStatus status={r.status} /></td>
                </tr>
              ))}
              <tr><td><strong>{t("erpTotal")}</strong></td>{COLS.map((c) => <td key={c} className="num"><strong><Tzs value={data.totals[c]} /></strong></td>)}<td /></tr>
            </tbody>
          </table>
        </div>
      )}

      {rates && (
        <GlassCard title={t("hrRatesInForce")} subtitle={t("hrRatesSub")} pad={false}>
          <div className="vf-table-wrap">
            <table className="table vf-table">
              <thead><tr><th>{t("erpName")}</th><th>{t("hrBase")}</th><th>{t("hrRate")}</th><th>{t("hrEffectiveFrom")}</th><th /></tr></thead>
              <tbody>
                {Object.values(rates.in_force).map((r) => (
                  <tr key={r.code}>
                    <td>{r.name}<span className="erp-cell-sub">{r.party === "employer" ? t("hrEmployer") : t("hrEmployee")}</span></td>
                    <td>{r.base}</td>
                    <td>{r.kind === "bands" ? (
                      <span className="erp-cell-sub">{r.bands?.map((b) => `${b.from.toLocaleString()}${b.to ? `-${b.to.toLocaleString()}` : "+"}: ${b.base ? `${b.base.toLocaleString()} + ` : ""}${b.rate}%`).join("; ")}</span>
                    ) : `${Number(r.rate)}%`}</td>
                    <td className="tnum">{formatDate(r.effective_from, locale)}</td>
                    <td>{can("hr.payroll.prepare") && r.kind === "percent" && <button className="btn btn-secondary btn-sm" onClick={() => setNewRate(r)}>{t("hrNewVersion")}</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="erp-muted" style={{ padding: "8px 16px" }}>{t("hrRatesHistory")} {rates.data.length}</p>
        </GlassCard>
      )}

      <FormDialog open={!!newRate} title={`${t("hrNewVersion")} · ${newRate?.name ?? ""}`} onClose={() => setNewRate(null)}
        intro={<p className="erp-muted">{t("hrNewVersionHint")}</p>}
        initial={{ rate: String(newRate?.rate ?? ""), effective_from: "" }}
        fields={[{ name: "rate", label: `${t("hrRate")} (%)`, type: "number", required: true }, { name: "effective_from", label: t("hrEffectiveFrom"), type: "date", required: true }]}
        onSubmit={async (v) => {
          if (!newRate) return;
          await api.post("/erp/hr/statutory-rates", { ...payload(v, ["rate"]), code: newRate.code, name: newRate.name, kind: "percent", base: newRate.base, party: newRate.party });
          toast(t("erpSaved"), undefined, "ok"); setNewRate(null); load();
        }} />
    </div>
  );
}

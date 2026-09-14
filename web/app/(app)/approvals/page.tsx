"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { formatDate, money } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { Figure, FigureStrip, SearchInput } from "@/components/app-ui";
import { VoucherList } from "@/components/voucher-bits";
import type { Voucher } from "@/lib/types";

type Kind = "all" | "bank" | "cash";

/**
 * Every voucher waiting on this person's step, laid out for deciding.
 *
 * Each row answers what is being asked, by whom, for how much, from which
 * department, and how far along the route it is — and leads to the voucher,
 * where the decision itself is taken behind a confirmation.
 */
export default function ApprovalsPage() {
  const { t, locale, company } = useApp();
  const [queue, setQueue] = useState<Voucher[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [q, setQ] = useState("");
  const [kind, setKind] = useState<Kind>("all");

  const load = useCallback(() => {
    setError(null);
    api.get<{ data: Voucher[] }>("/vouchers/pending")
      .then((r) => setQueue(r.data))
      .catch((err) => setError(err.message));
  }, []);

  useEffect(load, [load, locale]);

  const shown = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return (queue ?? []).filter((v) => (kind === "all" || v.kind === kind)
      && (!needle || [v.number, v.purpose, v.payee, v.requester?.name, v.department?.name].some((x) => x?.toLowerCase().includes(needle))));
  }, [queue, q, kind]);

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!queue) return <LoadingBlock rows={4} />;

  const sw = locale === "sw";
  const total = queue.reduce((sum, v) => sum + v.amount, 0);
  const oldest = [...queue].sort((a, b) => String(a.submitted_at ?? a.voucher_date).localeCompare(String(b.submitted_at ?? b.voucher_date)))[0];

  return (
    <div className="app-page">
      <PageHeader
        title={queue.length > 0 ? `${queue.length} ${queue.length === 1 ? t("voucherWord") : t("vouchersWord")} ${t("awaitingYou")}` : t("nothingAwaiting")}
        sub={t("signOnlyNote")}
        actions={<Link className="btn btn-secondary" href="/vouchers"><Icon name="ph-receipt" size={15} /> {t("voucherRegister")}</Link>}
      />

      {queue.length > 0 && (
        <div className="app-section">
          <FigureStrip>
            <Figure label={t("awaitingYou")} value={queue.length} tone="info" />
            <Figure label={t("total")} value={money(total, company?.currency)} />
            <Figure label={t("bank")} value={queue.filter((v) => v.kind === "bank").length} />
            <Figure label={t("cash")} value={queue.filter((v) => v.kind === "cash").length} />
            {oldest && <Figure label={sw ? "Inasubiri tangu" : "Waiting since"} value={formatDate(oldest.submitted_at ?? oldest.voucher_date, locale)} sub={oldest.number} />}
          </FigureStrip>
        </div>
      )}

      <section className="vf-panel">
        {queue.length > 0 && (
          <div className="app-toolbar">
            <div className="app-toolbar-main">
              <SearchInput value={q} onChange={setQ} placeholder={t("searchPh")} />
              <div className="seg seg-sm" role="tablist" aria-label={t("voucherFormat")}>
                {([["all", t("all")], ["bank", t("bank")], ["cash", t("cash")]] as const).map(([key, label]) => (
                  <button key={key} type="button" role="tab" aria-selected={kind === key} onClick={() => setKind(key)}>{label}</button>
                ))}
              </div>
            </div>
            <div className="app-toolbar-end"><span className="app-result-count">{t("showing")} {shown.length} {t("of")} {queue.length}</span></div>
          </div>
        )}

        {queue.length === 0 ? (
          <EmptyState tone="ok" icon="ph-check-circle" title={t("nothingAwaiting")} body={t("nothingAwaitingBody")}
            action={<Link className="btn btn-secondary" href="/vouchers"><Icon name="ph-receipt" size={15} /> {t("register")}</Link>} />
        ) : shown.length === 0 ? (
          <EmptyState icon="ph-magnifying-glass" title={t("noResults")} />
        ) : (
          <>
            <VoucherList vouchers={shown} bare />
            <div className="app-panel-foot"><Icon name="ph-shield-check" size={15} /><span>{t("clearedNote")}</span></div>
          </>
        )}
      </section>
    </div>
  );
}

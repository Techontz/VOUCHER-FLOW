"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { EmptyState, ErrorState, LoadingBlock, PageHeader } from "@/components/ui";
import { VoucherCard } from "@/components/voucher-bits";
import type { Voucher } from "@/lib/types";

export default function ApprovalsPage() {
  const { t, locale } = useApp();
  const [queue, setQueue] = useState<Voucher[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setError(null);
    api.get<{ data: Voucher[] }>("/vouchers/pending")
      .then((r) => setQueue(r.data))
      .catch((err) => setError(err.message));
  }, []);

  useEffect(load, [load, locale]);

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!queue) return <LoadingBlock rows={4} />;

  return (
    <div style={{ maxWidth: 1000 }}>
      <PageHeader
        kicker={t("approvals")}
        title={queue.length > 0 ? `${queue.length} ${queue.length === 1 ? t("voucherWord") : t("vouchersWord")} ${t("awaitingYou")}` : t("nothingAwaiting")}
        sub={t("signOnlyNote")}
      />

      {queue.length === 0 ? (
        <EmptyState icon="ph-check-square-offset" title={t("nothingAwaiting")} body={t("nothingAwaitingBody")}
          action={<Link className="btn btn-secondary" href="/vouchers">{t("register")}</Link>} />
      ) : (
        <div style={{ display: "grid", gap: "var(--space-3)" }}>
          {queue.map((voucher) => <VoucherCard key={voucher.id} voucher={voucher} />)}
        </div>
      )}
    </div>
  );
}

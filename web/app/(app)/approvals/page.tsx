"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import { VoucherList } from "@/components/voucher-bits";
import type { Voucher } from "@/lib/types";

/** Every voucher waiting on this person's step, as one list. */
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
    <div className="vf-dashboard">
      <PageHeader
        kicker={t("approvals")}
        title={queue.length > 0 ? `${queue.length} ${queue.length === 1 ? t("voucherWord") : t("vouchersWord")} ${t("awaitingYou")}` : t("nothingAwaiting")}
        sub={t("signOnlyNote")}
      />

      {queue.length === 0 ? (
        <div className="vf-panel">
          <EmptyState tone="ok" icon="ph-check-circle" title={t("nothingAwaiting")} body={t("nothingAwaitingBody")}
            action={<Link className="btn btn-secondary" href="/vouchers"><Icon name="ph-receipt" size={17} /> {t("register")}</Link>} />
        </div>
      ) : (
        <VoucherList vouchers={queue} />
      )}
    </div>
  );
}

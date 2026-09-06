"use client";

import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { groupByDay, relativeTime } from "@/lib/format";
import { EmptyState, ErrorState, Icon, LoadingBlock, PageHeader } from "@/components/ui";
import type { AppNotification, Paginated } from "@/lib/types";

export default function NotificationsPage() {
  const router = useRouter();
  const { t, locale, toast, reportError, refreshUnread } = useApp();
  const [items, setItems] = useState<AppNotification[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [unread, setUnread] = useState(0);

  const load = useCallback(() => {
    setError(null);
    api.get<Paginated<AppNotification>>("/notifications", { per_page: 50 })
      .then((r) => { setItems(r.data); setUnread(r.meta?.unread_count ?? 0); })
      .catch((err) => setError(err.message));
  }, []);

  useEffect(load, [load, locale]);

  async function markAll() {
    try {
      const res = await api.post<{ count: number }>("/notifications/read-all");
      toast("All caught up", `${res.count} notifications marked as read.`, "ok");
      load();
      void refreshUnread();
    } catch (err) {
      reportError(err, "Could not update notifications");
    }
  }

  async function open(item: AppNotification) {
    if (item.is_unread) {
      try { await api.post(`/notifications/${item.id}/read`); void refreshUnread(); } catch { /* non-blocking */ }
    }
    if (item.entity_type === "Voucher" && item.entity_id) router.push(`/vouchers/${item.entity_id}`);
    else load();
  }

  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!items) return <LoadingBlock rows={5} />;

  const groups = groupByDay(items, (item) => item.created_at);
  const labels: Record<string, string> = { today: t("today"), yesterday: t("yesterday"), earlier: t("earlier") };

  return (
    <div style={{ maxWidth: 820 }}>
      <PageHeader
        kicker={t("notifications")}
        title={unread > 0 ? `${unread} unread` : t("noNotifications")}
        actions={unread > 0 ? <button className="btn btn-secondary" onClick={markAll}><Icon name="ph-checks" size={15} /> {t("markAllRead")}</button> : undefined}
      />

      {items.length === 0 ? (
        <EmptyState icon="ph-bell-slash" title={t("noNotifications")} body="New approvals, decisions and billing events appear here." />
      ) : (
        groups.map((group) => (
          <section key={group.key} style={{ marginBottom: "var(--space-6)" }}>
            <div style={{ fontSize: 12, letterSpacing: ".12em", textTransform: "uppercase", color: "var(--color-neutral-600)", marginBottom: "var(--space-2)" }}>
              {labels[group.key]}
            </div>
            <div style={{ display: "grid", gap: 4 }}>
              {group.items.map((item) => (
                <button key={item.id} onClick={() => open(item)}
                  style={{
                    display: "flex", gap: "var(--space-3)", textAlign: "left", width: "100%",
                    border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)",
                    background: item.is_unread ? "var(--color-accent-100)" : "transparent",
                    padding: "var(--space-3)", cursor: "pointer", fontFamily: "var(--font-body)", color: "var(--color-text)",
                  }}>
                  <Icon name={item.icon} size={22} color="var(--color-accent-700)" />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontWeight: item.is_unread ? 600 : 400, fontSize: 15 }}>{item.title}</div>
                    {item.body && <div style={{ fontSize: 14, color: "var(--color-neutral-700)" }}>{item.body}</div>}
                  </div>
                  <div style={{ fontSize: 12.5, color: "var(--color-neutral-600)", whiteSpace: "nowrap" }}>
                    {relativeTime(item.created_at, locale)}
                  </div>
                </button>
              ))}
            </div>
          </section>
        ))
      )}
    </div>
  );
}

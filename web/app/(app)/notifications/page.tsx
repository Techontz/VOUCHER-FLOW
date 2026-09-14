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
    <div className="app-page app-inbox">
      <PageHeader
        title={t("notifications")}
        sub={unread > 0 ? `${unread} unread` : t("noNotifications")}
        actions={unread > 0 ? <button className="btn btn-secondary" onClick={markAll}><Icon name="ph-checks" size={15} /> {t("markAllRead")}</button> : undefined}
      />

      <section className="vf-panel">
        {items.length === 0 ? (
          <EmptyState icon="ph-bell-slash" title={t("noNotifications")} body="New approvals, decisions and billing events appear here." />
        ) : (
          groups.map((group) => (
            <div key={group.key} className="app-inbox-group">
              <div className="app-inbox-day">{labels[group.key]}</div>
              <ul className="app-inbox-list">
                {group.items.map((item) => (
                  <li key={item.id}>
                    <button type="button" onClick={() => open(item)} className="app-inbox-item" data-unread={item.is_unread || undefined}>
                      <span className="app-inbox-icon"><Icon name={item.icon} size={17} /></span>
                      <span className="app-inbox-text">
                        <strong>{item.title}</strong>
                        {item.body && <span>{item.body}</span>}
                      </span>
                      <span className="app-inbox-when">{relativeTime(item.created_at, locale)}</span>
                      {item.is_unread && <span className="app-inbox-dot" aria-label="Unread" />}
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          ))
        )}
      </section>
    </div>
  );
}

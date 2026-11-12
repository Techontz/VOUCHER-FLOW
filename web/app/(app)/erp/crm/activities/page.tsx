"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { type Paginated, useErp, useQueryValue } from "@/lib/erp";
import { ACTIVITY_LABEL, ACTIVITY_TYPES, type Activity, type ActivityType } from "@/lib/crm-types";
import { ErrorState, GlassCard, Icon, LoadingBlock, PageHeader, Pagination } from "@/components/ui";
import { SearchInput, Toolbar } from "@/components/app-ui";
import { ErpGate, FilterChips } from "@/components/erp-ui";
import { ActivityDialog, ActivityList, CrmTabs, usePeople } from "@/components/crm-ui";

export default function ActivitiesPage() {
  return <ErpGate module="crm" permission="crm.view"><Activities /></ErpGate>;
}

type Status = "open" | "today" | "overdue" | "done" | "";

function Activities() {
  const { t } = useApp();
  const { can } = useErp();
  const people = usePeople();
  const initial = useQueryValue("status");
  const [chosen, setStatus] = useState<Status | null>(null);
  const status: Status = chosen ?? ((initial as Status | null | undefined) || "open");
  const [type, setType] = useState<ActivityType | "">("");
  const [owner, setOwner] = useState("");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Paginated<Activity> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  const load = useCallback(() => {
    api.get<Paginated<Activity>>("/erp/crm/activities", { status: status || undefined, type: type || undefined, owner_id: owner || undefined, q: q || undefined, page })
      .then(setRows).catch((e) => setError(e.message));
  }, [status, type, owner, q, page]);
  useEffect(() => { const id = window.setTimeout(load, q ? 220 : 0); return () => window.clearTimeout(id); }, [load, q]);

  return (
    <div className="erp-page">
      <PageHeader title={t("crmNavActivities")} subtitle={t("crmActivitiesSub")}
        actions={can("crm.manage") && <button className="btn btn-primary" onClick={() => setCreating(true)}><Icon name="ph-plus" size={18} /> {t("crmNewActivity")}</button>} />
      <CrmTabs />

      <Toolbar end={<>
        <select className="input" aria-label={t("crmType")} value={type} onChange={(e) => { setType(e.target.value as ActivityType | ""); setPage(1); }} style={{ maxWidth: 180 }}>
          <option value="">{t("crmAllTypes")}</option>
          {ACTIVITY_TYPES.map((a) => <option key={a} value={a}>{t(ACTIVITY_LABEL[a])}</option>)}
        </select>
        {can("crm.view_all") && (
          <select className="input" aria-label={t("crmOwner")} value={owner} onChange={(e) => { setOwner(e.target.value); setPage(1); }} style={{ maxWidth: 200 }}>
            <option value="">{t("crmEveryone")}</option>
            {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        )}
      </>}>
        <SearchInput value={q} onChange={(v) => { setQ(v); setPage(1); }} placeholder={`${t("erpSearch")}, ${t("crmSubject")}`} />
        <FilterChips<Status> value={status} onChange={(v) => { setStatus(v); setPage(1); }} items={[
          { value: "open", label: t("crmFilterOpen") }, { value: "today", label: t("crmFilterToday") },
          { value: "overdue", label: t("crmFilterOverdue") }, { value: "done", label: t("crmFilterDone") }, { value: "", label: t("erpAll") },
        ]} />
      </Toolbar>

      {error ? <ErrorState message={error} onRetry={load} /> : !rows ? <LoadingBlock /> : (
        <>
          <GlassCard pad={false}>
            <ActivityList rows={rows.data} onChanged={load} manage={can("crm.manage")} empty={t("crmNoActivities")} />
          </GlassCard>
          <Pagination page={rows.current_page} lastPage={rows.last_page} total={rows.total} onChange={setPage} />
        </>
      )}

      <ActivityDialog open={creating} onClose={() => setCreating(false)} onSaved={load} />
    </div>
  );
}

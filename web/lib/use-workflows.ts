"use client";

import { useEffect, useState } from "react";
import { api } from "./api";
import { useApp } from "./app-context";
import type { Workflow } from "./types";

/*
 * The company's workflows, fetched once and shared by every list on the page.
 *
 * Keyed by company, never global: signing out of one tenant and into another in
 * the same tab must not show the first company's approval routes against the
 * second company's vouchers. The in-flight promise is shared too, so a
 * dashboard that renders three lists makes one request, not three.
 */

const cache = new Map<number, Workflow[]>();
const inflight = new Map<number, Promise<Workflow[]>>();

function load(companyId: number): Promise<Workflow[]> {
  const cached = cache.get(companyId);
  if (cached) return Promise.resolve(cached);

  const pending = inflight.get(companyId);
  if (pending) return pending;

  const request = api.get<{ data: Workflow[] }>("/workflows")
    .then((response) => {
      cache.set(companyId, response.data);
      return response.data;
    })
    .finally(() => inflight.delete(companyId));

  inflight.set(companyId, request);
  return request;
}

/** Drops cached routes — call after a workflow is edited. */
export function invalidateWorkflows(companyId?: number | null) {
  if (companyId == null) cache.clear();
  else cache.delete(companyId);
}

export function useWorkflows(): Workflow[] | null {
  const { company, user } = useApp();
  const companyId = company?.id ?? null;
  const [workflows, setWorkflows] = useState<Workflow[] | null>(
    companyId != null ? cache.get(companyId) ?? null : null,
  );

  useEffect(() => {
    // A platform operator has no company, and so no routes of their own.
    if (companyId == null || !user) return;

    let live = true;
    load(companyId)
      .then((data) => { if (live) setWorkflows(data); })
      // Progress is an enhancement on a list; a failure here must not break it.
      .catch(() => { if (live) setWorkflows([]); });

    return () => { live = false; };
  }, [companyId, user]);

  return workflows;
}

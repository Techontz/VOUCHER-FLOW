"use client";

import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import type { Bom } from "@/lib/production-api";
import { EmptyState, ErrorState, LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { BomForm } from "@/components/production-bom-form";

export default function EditBomPage() {
  return <ErpGate module="production" permission="production.manage"><EditBom /></ErpGate>;
}

function EditBom() {
  const { t } = useApp();
  const { id } = useParams<{ id: string }>();
  const [bom, setBom] = useState<Bom | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Bom }>(`/erp/production/boms/${id}`).then((r) => setBom(r.data)).catch((e) => setError(e.message));
  }, [id]);

  if (error) return <ErrorState message={error} />;
  if (!bom) return <LoadingBlock rows={5} />;
  if ((bom.orders_count ?? 0) > 0) return <EmptyState icon="ph-lock-simple" title={t("prdBomFrozen")} body={t("prdBomFrozenBody")} />;
  return <BomForm existing={bom} />;
}

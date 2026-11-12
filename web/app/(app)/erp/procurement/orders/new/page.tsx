"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useQueryValue } from "@/lib/erp";
import type { Requisition } from "@/lib/procurement-api";
import { ErrorState, LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { OrderForm } from "@/components/procurement-order-form";

export default function NewOrderPage() {
  return <ErpGate module="procurement" permission="procurement.order"><NewOrder /></ErpGate>;
}

function NewOrder() {
  const requisitionId = useQueryValue("requisition");
  const [requisition, setRequisition] = useState<Requisition | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (requisitionId) api.get<{ data: Requisition }>(`/erp/procurement/requisitions/${requisitionId}`).then((r) => setRequisition(r.data)).catch((e) => setError(e.message));
  }, [requisitionId]);

  if (error) return <ErrorState message={error} />;
  if (requisitionId === undefined || (requisitionId && !requisition)) return <LoadingBlock rows={5} />;
  return <OrderForm requisition={requisition} />;
}

"use client";

import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { SalesOrder } from "@/lib/sales-api";
import { ErrorState, LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { SalesDocForm } from "@/components/sales-ui";

export default function EditOrderPage() {
  return <ErpGate module="sales" permission="sales.order"><EditOrder /></ErpGate>;
}

function EditOrder() {
  const { id } = useParams<{ id: string }>();
  const [doc, setDoc] = useState<SalesOrder | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { api.get<{ data: SalesOrder }>(`/erp/sales/orders/${id}`).then((r) => setDoc(r.data)).catch((e) => setError(e.message)); }, [id]);
  if (error) return <ErrorState message={error} />;
  if (!doc) return <LoadingBlock rows={5} />;
  return <SalesDocForm kind="order" existing={doc} />;
}

"use client";

import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { Order } from "@/lib/procurement-api";
import { ErrorState, LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { OrderForm } from "@/components/procurement-order-form";

export default function EditOrderPage() {
  return <ErpGate module="procurement" permission="procurement.order"><EditOrder /></ErpGate>;
}

function EditOrder() {
  const { id } = useParams<{ id: string }>();
  const [order, setOrder] = useState<Order | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Order }>(`/erp/procurement/orders/${id}`).then((r) => setOrder(r.data)).catch((e) => setError(e.message));
  }, [id]);

  if (error) return <ErrorState message={error} />;
  if (!order) return <LoadingBlock rows={5} />;
  return <OrderForm existing={order} />;
}

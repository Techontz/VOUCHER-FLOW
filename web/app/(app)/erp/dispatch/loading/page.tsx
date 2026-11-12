"use client";

import { useQueryValue } from "@/lib/erp";
import { LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { LoadingRegister, type Stage } from "@/components/sales-dispatch";

export default function LoadingOrdersPage() {
  return <ErpGate module="dispatch" permission="dispatch.view"><LoadingOrdersGate /></ErpGate>;
}

function LoadingOrdersGate() {
  const stage = useQueryValue("stage");
  if (stage === undefined) return <LoadingBlock />;
  return <LoadingRegister title="salLoadingOrders" subtitle="salLoadingOrdersSub" initial={(stage ?? "") as Stage} />;
}

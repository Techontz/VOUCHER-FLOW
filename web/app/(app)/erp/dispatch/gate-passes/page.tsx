"use client";

import { ErpGate } from "@/components/erp-ui";
import { LoadingRegister } from "@/components/sales-dispatch";

export default function GatePassesPage() {
  return <ErpGate module="dispatch" permission="dispatch.view"><LoadingRegister title="salGatePasses" subtitle="salGatePassesSub" fixed="gate_passes" columns="gate_passes" /></ErpGate>;
}

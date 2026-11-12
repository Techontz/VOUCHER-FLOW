"use client";

import { ErpGate } from "@/components/erp-ui";
import { LoadingRegister } from "@/components/sales-dispatch";

/** Trucks out of the gate, waiting for proof of delivery. */
export default function DeliveriesPage() {
  return <ErpGate module="dispatch" permission="dispatch.view"><LoadingRegister title="salProofOfDelivery" subtitle="salProofOfDeliverySub" fixed="in_transit" /></ErpGate>;
}

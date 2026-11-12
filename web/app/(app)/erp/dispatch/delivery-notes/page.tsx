"use client";

import { ErpGate } from "@/components/erp-ui";
import { LoadingRegister } from "@/components/sales-dispatch";

export default function DeliveryNotesPage() {
  return <ErpGate module="dispatch" permission="dispatch.view"><LoadingRegister title="salDeliveryNotes" subtitle="salDeliveryNotesSub" fixed="delivery_notes" columns="delivery_notes" /></ErpGate>;
}

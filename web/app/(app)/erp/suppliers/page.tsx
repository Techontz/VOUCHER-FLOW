"use client";

import { ErpGate } from "@/components/erp-ui";
import { PartyRegister } from "@/components/erp-parties";

export default function SuppliersPage() {
  return <ErpGate module="procurement" permission="suppliers.view"><PartyRegister kind="suppliers" /></ErpGate>;
}

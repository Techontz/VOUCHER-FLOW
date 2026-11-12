"use client";

import { useParams } from "next/navigation";
import { ErpGate } from "@/components/erp-ui";
import { TripDetail } from "@/components/fleet-trip";

export default function TripPage() {
  const { id } = useParams<{ id: string }>();
  return <ErpGate module="fleet" permission="fleet.view"><TripDetail id={id} /></ErpGate>;
}

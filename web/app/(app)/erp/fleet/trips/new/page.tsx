"use client";

import { ErpGate } from "@/components/erp-ui";
import { TripForm } from "@/components/fleet-trip";

export default function NewTripPage() {
  return <ErpGate module="fleet" permission="fleet.trips"><TripForm /></ErpGate>;
}

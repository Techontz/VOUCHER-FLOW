"use client";

import { ErpGate } from "@/components/erp-ui";
import { TripList } from "@/components/fleet-trip-list";

export default function TripsPage() {
  return <ErpGate module="fleet" permission="fleet.view"><TripList /></ErpGate>;
}

"use client";

import { ErpGate } from "@/components/erp-ui";
import { TripList } from "@/components/fleet-trip-list";

export default function MyTripsPage() {
  return <ErpGate module="fleet" permission="fleet.own"><TripList mine /></ErpGate>;
}

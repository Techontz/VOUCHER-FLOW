"use client";

import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { Trip } from "@/lib/fleet";
import { ErrorState, LoadingBlock } from "@/components/ui";
import { ErpGate } from "@/components/erp-ui";
import { TripForm } from "@/components/fleet-trip";

export default function EditTripPage() {
  return <ErpGate module="fleet" permission="fleet.trips"><EditTrip /></ErpGate>;
}

function EditTrip() {
  const { id } = useParams<{ id: string }>();
  const [trip, setTrip] = useState<Trip | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ data: Trip }>(`/erp/fleet/trips/${id}`).then((r) => setTrip(r.data)).catch((e) => setError(e.message));
  }, [id]);

  if (error) return <ErrorState message={error} />;
  if (!trip) return <LoadingBlock rows={6} />;
  return <TripForm trip={trip} />;
}

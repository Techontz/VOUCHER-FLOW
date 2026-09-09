"use client";

import type { CSSProperties } from "react";

/**
 * Official marks for the printed voucher.
 *
 * These stand in for the rubber stamps a finance office actually uses, so they
 * are drawn as ink on paper: a ruled border, tracked capitals, the acting
 * officer's name and the moment it happened. They are deliberately plain —
 * a stamp that looks decorative reads as fake.
 */
export type StampKind = "signed" | "approved" | "paid" | "rejected" | "returned";

const INK: Record<StampKind, { colour: string; word: string }> = {
  signed: { colour: "#1f3a8a", word: "SIGNED" },
  approved: { colour: "#0f7a54", word: "APPROVED" },
  paid: { colour: "#a3183a", word: "PAID" },
  rejected: { colour: "#a3183a", word: "REJECTED" },
  returned: { colour: "#8a5a00", word: "RETURNED" },
};

export function Stamp({
  kind, name, date, reference, tilt = -4, scale = 1,
}: {
  kind: StampKind;
  /** Who applied it. Printed inside the frame, as a stamp carries a name. */
  name?: string | null;
  date?: string | null;
  /** Payment reference, for a PAID mark. */
  reference?: string | null;
  tilt?: number;
  scale?: number;
}) {
  const { colour, word } = INK[kind];

  return (
    <span
      role="img"
      aria-label={`${word}${name ? ` by ${name}` : ""}${date ? ` on ${date}` : ""}`}
      style={{
        display: "inline-block",
        transform: `rotate(${tilt}deg) scale(${scale})`,
        transformOrigin: "center",
        border: `2px solid ${colour}`,
        borderRadius: 4,
        padding: "4px 10px 3px",
        color: colour,
        // A second rule inside the frame, the way a real stamp is cut.
        boxShadow: `inset 0 0 0 1px ${colour}`,
        background: "transparent",
        lineHeight: 1.12,
        textAlign: "center",
        whiteSpace: "nowrap",
      }}
    >
      <span style={{
        display: "block",
        fontSize: 15, fontWeight: 800, letterSpacing: ".18em",
        fontFamily: "var(--font-heading)",
      }}>{word}</span>

      {name && (
        <span style={{ display: "block", fontSize: 8, fontWeight: 700, letterSpacing: ".08em", marginTop: 2 }}>
          {name.toUpperCase()}
        </span>
      )}
      {(date || reference) && (
        <span style={{ display: "block", fontSize: 7.5, fontWeight: 600, letterSpacing: ".06em", opacity: .9 }}>
          {[reference, date].filter(Boolean).join(" · ")}
        </span>
      )}
    </span>
  );
}

/**
 * One column of the authorisation band: who did it, their mark, their
 * signature and when. Every voucher carries the same four columns so the
 * document reads identically whatever stage it has reached.
 */
export function AuthorisationBlock({
  caption, name, title, date, signature, stamp, reference, note, emphasis,
}: {
  caption: string;
  name?: string | null;
  title?: string | null;
  date?: string | null;
  signature?: string | null;
  stamp?: StampKind;
  reference?: string | null;
  note?: string | null;
  emphasis?: boolean;
}) {
  const done = !!(name && date);

  const frame: CSSProperties = {
    border: `1px solid ${emphasis && done ? "#c3d4f5" : "#e2e7ef"}`,
    borderRadius: 6,
    background: emphasis && done ? "#f6f9ff" : "#fcfdff",
    padding: "9px 10px 8px",
    display: "flex",
    flexDirection: "column",
    minHeight: 104,
    breakInside: "avoid",
  };

  return (
    <div style={frame}>
      <div style={{
        fontSize: 7.5, fontWeight: 800, letterSpacing: ".13em",
        textTransform: "uppercase", color: "#8892a6",
      }}>{caption}</div>

      {/* The mark and the pen stroke share the same band, so a completed
          column always has visible weight and an outstanding one is plainly
          empty rather than ambiguous. */}
      <div style={{
        flex: 1, display: "flex", alignItems: "center", justifyContent: "center",
        gap: 8, padding: "6px 0 4px", minHeight: 44,
      }}>
        {done ? (
          <>
            {signature && (
              <img src={signature} alt="" style={{ maxHeight: 34, maxWidth: 78, objectFit: "contain" }} />
            )}
            {stamp && <Stamp kind={stamp} date={date} reference={reference} scale={.86} />}
            {!signature && !stamp && (
              <span style={{ fontFamily: "var(--font-heading)", fontStyle: "italic", fontSize: 16, color: "#0b1220" }}>
                {name}
              </span>
            )}
          </>
        ) : (
          <span style={{ fontSize: 8.5, letterSpacing: ".08em", color: "#b3bccd", textTransform: "uppercase" }}>
            {note ?? "Pending"}
          </span>
        )}
      </div>

      <div style={{ borderTop: "1px solid #d7dde8", paddingTop: 5, fontSize: 8.5, lineHeight: 1.42 }}>
        <div style={{ fontWeight: 700, color: "#0b1220" }}>{name ?? "—"}</div>
        <div style={{ color: "#5f6b80" }}>{title ?? ""}</div>
        {date && <div style={{ color: "#8892a6", fontVariantNumeric: "tabular-nums" }}>{date}</div>}
      </div>
    </div>
  );
}

/** The status band shown across the top of the document once it is closed. */
export function DocumentStatusMark({ kind, date, reference }: {
  kind: StampKind; date?: string | null; reference?: string | null;
}) {
  return (
    <div style={{ position: "absolute", top: 92, right: 54, opacity: .92, pointerEvents: "none" }}>
      <Stamp kind={kind} date={date} reference={reference} tilt={-9} scale={1.35} />
    </div>
  );
}

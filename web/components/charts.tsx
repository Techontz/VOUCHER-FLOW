"use client";

import { useId, useMemo, useState, type KeyboardEvent, type ReactNode } from "react";

/*
 * Small charts for the platform screens, drawn by hand so the app carries no
 * chart library.
 *
 * Every chart is sized by its container: the plot is an SVG that stretches
 * to the width it is given (lines keep their weight through
 * vector-effect), while text, dots and tooltips are HTML laid over it, so
 * labels stay crisp and readable on a 390px phone. Colours come from CSS
 * variables in styles/platform.css, defined for light and dark, so a chart
 * follows the theme without a re-render. Each chart animates in once on
 * mount (a left-to-right reveal, bars that grow, a ring that draws) and sits
 * still for anyone who asked for reduced motion. Each also carries a
 * screen-reader table of the numbers it draws.
 */

export type SeriesTone = "s1" | "s2" | "s3" | "s4" | "s5" | "s6" | "s7" | "s8" | "ok" | "warn" | "bad" | "info" | "muted";

export interface Point {
  label: string;
  value: number;
}

const toneVar = (tone: SeriesTone) => `var(--pf-${tone})`;

/** A "nice" upper bound for an axis: 1, 2, 2.5 or 5 times a power of ten. */
function niceMax(value: number): number {
  if (value <= 0) return 1;
  const exp = Math.pow(10, Math.floor(Math.log10(value)));
  const f = value / exp;
  const nice = f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10;
  return nice * exp;
}

/** Short numbers for axes: 1.2K, 3.4M. */
export function compactNumber(value: number): string {
  const abs = Math.abs(value);
  if (abs >= 1e9) return `${+(value / 1e9).toFixed(1)}B`;
  if (abs >= 1e6) return `${+(value / 1e6).toFixed(1)}M`;
  if (abs >= 1e3) return `${+(value / 1e3).toFixed(1)}K`;
  return `${Math.round(value)}`;
}

/** The table a screen reader gets in place of the drawing. */
function SrTable({ caption, head, rows }: { caption: string; head: string[]; rows: ReactNode[][] }) {
  return (
    <table className="sr-only">
      <caption>{caption}</caption>
      <thead><tr>{head.map((h, i) => <th key={i} scope="col">{h}</th>)}</tr></thead>
      <tbody>{rows.map((r, i) => <tr key={i}>{r.map((c, j) => <td key={j}>{c}</td>)}</tr>)}</tbody>
    </table>
  );
}

/* ─────────────────────────────────────────────────────────── area ── */

/**
 * One measure over time: a 2px line over a soft gradient, with a crosshair
 * and tooltip on hover, touch or the arrow keys.
 *
 *   <AreaChart label="Revenue" data={[{ label: "Jan", value: 1200 }]} format={money} />
 */
export function AreaChart({
  data, label, format = compactNumber, height = 240, tone = "s1", valueLabel,
}: {
  data: Point[];
  label: string;
  format?: (value: number) => string;
  height?: number;
  tone?: SeriesTone;
  /** The name of the measure in the tooltip and the screen-reader table. */
  valueLabel?: string;
}) {
  const id = useId().replace(/:/g, "");
  const [active, setActive] = useState<number | null>(null);
  const n = data.length;
  const max = niceMax(Math.max(0, ...data.map((d) => d.value)));
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => f * max);

  // The plot runs 0..100 across and 0..100 down, stretched to the box.
  const x = (i: number) => (n <= 1 ? 50 : (i / (n - 1)) * 100);
  const y = (v: number) => 100 - (v / max) * 100;
  const line = data.map((d, i) => `${i ? "L" : "M"}${x(i).toFixed(3)},${y(d.value).toFixed(3)}`).join(" ");
  const area = n ? `${line} L100,100 L0,100 Z` : "";

  const pick = (clientX: number, rect: DOMRect) => {
    const f = (clientX - rect.left) / rect.width;
    setActive(Math.max(0, Math.min(n - 1, Math.round(f * (n - 1)))));
  };

  const onKey = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key === "ArrowRight") { e.preventDefault(); setActive((a) => Math.min(n - 1, (a ?? -1) + 1)); }
    if (e.key === "ArrowLeft") { e.preventDefault(); setActive((a) => Math.max(0, (a ?? n) - 1)); }
    if (e.key === "Escape") setActive(null);
  };

  const point = active !== null ? data[active] : null;
  // Every second month on a crowded axis, so labels never collide on a phone.
  const step = n > 8 ? 2 : 1;

  return (
    <figure className="pf-chart" aria-label={label} style={{ ["--pf-tone" as string]: toneVar(tone) }}>
      <div className="pf-chart-body">
        <div className="pf-yaxis" aria-hidden="true">
          {ticks.slice().reverse().map((t, i) => <span key={i}>{format(t)}</span>)}
        </div>
        <div className="pf-plot" style={{ height }}
          tabIndex={0} role="img" aria-label={`${label}. Use the arrow keys to read each month.`}
          onPointerMove={(e) => pick(e.clientX, e.currentTarget.getBoundingClientRect())}
          onPointerDown={(e) => pick(e.clientX, e.currentTarget.getBoundingClientRect())}
          onPointerLeave={() => setActive(null)}
          onBlur={() => setActive(null)}
          onKeyDown={onKey}>
          <svg className="pf-svg pf-reveal" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
            <defs>
              <linearGradient id={`g${id}`} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" style={{ stopColor: "var(--pf-tone)", stopOpacity: 0.28 }} />
                <stop offset="100%" style={{ stopColor: "var(--pf-tone)", stopOpacity: 0 }} />
              </linearGradient>
            </defs>
            {ticks.map((t, i) => (
              <line key={`${t}-${i}`} className="pf-grid" x1="0" x2="100" y1={y(t)} y2={y(t)} vectorEffect="non-scaling-stroke" />
            ))}
            {n > 0 && <path d={area} fill={`url(#g${id})`} />}
            {n > 0 && <path d={line} className="pf-line" vectorEffect="non-scaling-stroke" />}
            {point && active !== null && (
              <line className="pf-cross" x1={x(active)} x2={x(active)} y1="0" y2="100" vectorEffect="non-scaling-stroke" />
            )}
          </svg>
          {point && active !== null && (
            <>
              <span className="pf-dot" style={{ left: `${x(active)}%`, top: `${y(point.value)}%` }} aria-hidden="true" />
              <div className="pf-tip" role="status"
                style={{ left: `${x(active)}%`, top: `${y(point.value)}%` }}
                data-edge={x(active) > 70 ? "end" : x(active) < 30 ? "start" : undefined}>
                <span className="pf-tip-label">{point.label}</span>
                <span className="pf-tip-value tnum">{format(point.value)}</span>
                {valueLabel && <span className="pf-tip-sub">{valueLabel}</span>}
              </div>
            </>
          )}
        </div>
        <span aria-hidden="true" />
        <div className="pf-xaxis" aria-hidden="true">
          {data.map((d, i) => (
            <span key={`${d.label}-${i}`} style={{ left: `${x(i)}%` }} data-skip={i % step !== (n - 1) % step ? "" : undefined}>{d.label}</span>
          ))}
        </div>
      </div>
      <SrTable caption={label} head={["", valueLabel ?? label]} rows={data.map((d) => [d.label, format(d.value)])} />
    </figure>
  );
}

/* ─────────────────────────────────────────────────────────── bars ── */

export interface BarSeries {
  name: string;
  values: number[];
  tone?: SeriesTone;
}

/**
 * Columns per period, one or two series side by side, with a tooltip per
 * column group. Bars grow from the baseline on mount.
 */
export function BarChart({
  labels, series, label, format = compactNumber, height = 220,
}: {
  labels: string[];
  series: BarSeries[];
  label: string;
  format?: (value: number) => string;
  height?: number;
}) {
  const [active, setActive] = useState<number | null>(null);
  const max = niceMax(Math.max(0, ...series.flatMap((s) => s.values)));
  const ticks = [0, 0.5, 1].map((f) => f * max);
  const step = labels.length > 8 ? 2 : 1;
  const n = labels.length;

  return (
    <figure className="pf-chart" aria-label={label}>
      {series.length > 1 && <Legend items={series.map((s, i) => ({ label: s.name, tone: s.tone ?? (`s${i + 1}` as SeriesTone) }))} />}
      <div className="pf-chart-body">
        <div className="pf-yaxis" aria-hidden="true">
          {ticks.slice().reverse().map((t, i) => <span key={i}>{format(t)}</span>)}
        </div>
        <div className="pf-plot pf-bars" style={{ height }} onPointerLeave={() => setActive(null)}>
          <div className="pf-gridlines" aria-hidden="true">{ticks.map((t, i) => <span key={i} style={{ bottom: `${(t / max) * 100}%` }} />)}</div>
          {labels.map((l, i) => (
            <button key={`${l}-${i}`} type="button" className="pf-bargroup" data-active={active === i ? "" : undefined}
              onPointerEnter={() => setActive(i)} onFocus={() => setActive(i)} onBlur={() => setActive(null)}
              aria-label={`${l}: ${series.map((s) => `${s.name} ${format(s.values[i] ?? 0)}`).join(", ")}`}>
              {series.map((s, si) => (
                <span key={s.name} className="pf-bar"
                  style={{
                    height: `${((s.values[i] ?? 0) / max) * 100}%`,
                    background: toneVar(s.tone ?? (`s${si + 1}` as SeriesTone)),
                    animationDelay: `${i * 35}ms`,
                  }} />
              ))}
              {active === i && (
                <span className="pf-tip pf-tip-bar" role="status" data-edge={i / Math.max(1, n - 1) > 0.7 ? "end" : i / Math.max(1, n - 1) < 0.3 ? "start" : undefined}>
                  <span className="pf-tip-label">{l}</span>
                  {series.map((s, si) => (
                    <span key={s.name} className="pf-tip-row">
                      <i style={{ background: toneVar(s.tone ?? (`s${si + 1}` as SeriesTone)) }} />
                      {series.length > 1 && <span>{s.name}</span>}
                      <strong className="tnum">{format(s.values[i] ?? 0)}</strong>
                    </span>
                  ))}
                </span>
              )}
            </button>
          ))}
        </div>
        <span aria-hidden="true" />
        <div className="pf-xaxis pf-xaxis-bands" aria-hidden="true">
          {labels.map((l, i) => <span key={`${l}-${i}`} data-skip={i % step !== (n - 1) % step ? "" : undefined}>{l}</span>)}
        </div>
      </div>
      <SrTable caption={label} head={["", ...series.map((s) => s.name)]} rows={labels.map((l, i) => [l, ...series.map((s) => format(s.values[i] ?? 0))])} />
    </figure>
  );
}

/* ────────────────────────────────────────────────────────── legend ── */

export function Legend({ items }: { items: { label: string; tone: SeriesTone }[] }) {
  return (
    <ul className="pf-legend">
      {items.map((it) => (
        <li key={it.label}><i style={{ background: toneVar(it.tone) }} aria-hidden="true" />{it.label}</li>
      ))}
    </ul>
  );
}

/* ─────────────────────────────────────────────────────────── donut ── */

export interface Slice {
  key: string;
  label: string;
  value: number;
  tone?: SeriesTone;
}

/**
 * Parts of a whole: a ring with the total in its centre and a legend with
 * each part's count and share. More than six parts fold into "Other".
 */
export function DonutChart({
  slices, label, centerLabel, otherLabel = "Other", format = (v: number) => v.toLocaleString("en-US"),
}: {
  slices: Slice[];
  label: string;
  centerLabel: string;
  otherLabel?: string;
  format?: (value: number) => string;
}) {
  const [active, setActive] = useState<string | null>(null);

  const parts = useMemo(() => {
    const sorted = slices.filter((s) => s.value > 0);
    if (sorted.length <= 6) return sorted.map((s, i) => ({ ...s, tone: s.tone ?? (`s${i + 1}` as SeriesTone) }));
    const head = sorted.slice(0, 5).map((s, i) => ({ ...s, tone: s.tone ?? (`s${i + 1}` as SeriesTone) }));
    const rest = sorted.slice(5).reduce((sum, s) => sum + s.value, 0);
    return [...head, { key: "__other", label: otherLabel, value: rest, tone: "muted" as SeriesTone }];
  }, [slices, otherLabel]);

  const total = parts.reduce((sum, s) => sum + s.value, 0);
  const r = 46;
  const c = 2 * Math.PI * r;
  // A hairline of surface between neighbouring parts, none for a single one.
  const gap = parts.length > 1 ? 1.6 : 0;
  let offset = 0;
  const shown = active ? parts.find((p) => p.key === active) : null;

  return (
    <figure className="pf-donut" aria-label={label}>
      <div className="pf-donut-ring">
        <svg viewBox="0 0 120 120" aria-hidden="true">
          <circle cx="60" cy="60" r={r} className="pf-donut-track" />
          {total > 0 && parts.map((p, i) => {
            const len = (p.value / total) * c;
            const dash = Math.max(0.001, len - gap);
            const el = (
              <circle key={p.key} cx="60" cy="60" r={r} className="pf-donut-seg"
                strokeDasharray={`${dash} ${c - dash}`} strokeDashoffset={-offset}
                data-dim={active && active !== p.key ? "" : undefined}
                style={{ stroke: toneVar(p.tone), animationDelay: `${i * 70}ms` }}
                onPointerEnter={() => setActive(p.key)} onPointerLeave={() => setActive(null)} />
            );
            offset += len;
            return el;
          })}
        </svg>
        <div className="pf-donut-center" aria-hidden="true">
          <strong className="tnum">{format(shown ? shown.value : total)}</strong>
          <span>{shown ? shown.label : centerLabel}</span>
        </div>
      </div>
      <ul className="pf-donut-legend">
        {parts.map((p) => (
          <li key={p.key} data-active={active === p.key ? "" : undefined}>
            <button type="button" onPointerEnter={() => setActive(p.key)} onPointerLeave={() => setActive(null)}
              onFocus={() => setActive(p.key)} onBlur={() => setActive(null)}>
              <i style={{ background: toneVar(p.tone) }} aria-hidden="true" />
              <span className="pf-donut-name">{p.label}</span>
              <span className="pf-donut-val tnum">{format(p.value)}</span>
              <span className="pf-donut-pct tnum">{total ? Math.round((p.value / total) * 100) : 0}%</span>
            </button>
          </li>
        ))}
      </ul>
      <SrTable caption={label} head={["", "", "%"]} rows={parts.map((p) => [p.label, format(p.value), `${total ? Math.round((p.value / total) * 100) : 0}%`])} />
    </figure>
  );
}

/* ──────────────────────────────────────────────────── horizontal bars ── */

export interface HBarRow {
  key: string;
  label: ReactNode;
  value: number;
  /** Shown at the end of the row in place of the raw value. */
  display?: ReactNode;
  /** Muted badge after the label, e.g. "Coming soon". */
  note?: ReactNode;
  /** The bar's length out of this (defaults to the largest value). */
  max?: number;
}

/** A ranked list with a bar under each label, for adoption and leaderboards. */
export function HBarList({ rows, label, tone = "s1" }: { rows: HBarRow[]; label: string; tone?: SeriesTone }) {
  const max = Math.max(1, ...rows.map((r) => r.max ?? r.value));
  return (
    <ul className="pf-hbars" aria-label={label} style={{ ["--pf-tone" as string]: toneVar(tone) }}>
      {rows.map((r, i) => (
        <li key={r.key}>
          <div className="pf-hbar-top">
            <span className="pf-hbar-label">{r.label}{r.note && <span className="pf-hbar-note">{r.note}</span>}</span>
            <span className="pf-hbar-value tnum">{r.display ?? r.value.toLocaleString("en-US")}</span>
          </div>
          <div className="pf-hbar-track" aria-hidden="true">
            <span style={{ width: `${r.value > 0 ? Math.max(2, (r.value / (r.max ?? max)) * 100) : 0}%`, animationDelay: `${i * 45}ms` }} />
          </div>
        </li>
      ))}
    </ul>
  );
}

/* ──────────────────────────────────────────────────────── sparkline ── */

/** A tiny trend line for a stat card; decorative, the number beside it carries the meaning. */
export function Sparkline({ values, tone = "s1", height = 36 }: { values: number[]; tone?: SeriesTone; height?: number }) {
  const id = useId().replace(/:/g, "");
  if (values.length < 2) return null;
  const max = Math.max(...values);
  const min = Math.min(...values);
  const span = max - min || 1;
  const pts = values.map((v, i) => `${((i / (values.length - 1)) * 100).toFixed(2)},${(92 - ((v - min) / span) * 84).toFixed(2)}`);
  return (
    <svg className="pf-spark pf-reveal" viewBox="0 0 100 100" preserveAspectRatio="none" style={{ height, ["--pf-tone" as string]: toneVar(tone) }} aria-hidden="true">
      <defs>
        <linearGradient id={`s${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" style={{ stopColor: "var(--pf-tone)", stopOpacity: 0.22 }} />
          <stop offset="100%" style={{ stopColor: "var(--pf-tone)", stopOpacity: 0 }} />
        </linearGradient>
      </defs>
      <path d={`M${pts.join(" L")} L100,100 L0,100 Z`} fill={`url(#s${id})`} />
      <path d={`M${pts.join(" L")}`} className="pf-line" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

/* ──────────────────────────────────────────────────────────── meter ── */

/** Usage against a limit, with the numbers spelled out beside the bar. */
export function UsageMeter({ label, used, limit, unlimitedLabel, unit = "" }: {
  label: ReactNode; used: number; limit: number | null; unlimitedLabel: string; unit?: string;
}) {
  const pct = limit ? Math.min(100, Math.round((used / Math.max(1, limit)) * 100)) : null;
  const tone = pct === null ? "ok" : pct >= 100 ? "bad" : pct >= 80 ? "warn" : "ok";
  return (
    <div className="pf-meter" data-tone={tone}>
      <div className="pf-meter-top">
        <span>{label}</span>
        <strong className="tnum">
          {used.toLocaleString("en-US")}{unit && ` ${unit}`}
          <span className="pf-meter-of"> / {limit === null ? unlimitedLabel : `${limit.toLocaleString("en-US")}${unit && ` ${unit}`}`}</span>
        </strong>
      </div>
      <div className="pf-meter-track" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct ?? 0}
        aria-valuetext={limit === null ? unlimitedLabel : `${pct}%`}>
        <span style={{ width: `${pct === null ? 100 : Math.max(pct ? 2 : 0, pct)}%` }} data-unlimited={pct === null ? "" : undefined} />
      </div>
    </div>
  );
}

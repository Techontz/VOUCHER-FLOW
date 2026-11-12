import type { ReactNode } from "react";
import type { Area, AreaKey } from "@/lib/areas";

/*
 * App icons: a white tile with a soft shadow, holding a flat illustration of
 * two or three overlapping shapes. The overlaps multiply, so where two colours
 * cross a third, deeper one appears, the depth comes from the drawing rather
 * than from gradients. One palette for every app keeps the set coherent.
 */

const C = {
  blue: "#3D7BFA", sky: "#5BC6F2", navy: "#24386E", coral: "#FF7759",
  amber: "#FFBE3D", mint: "#2CC4A2", rose: "#F0628C", violet: "#7B5CD6",
};

/** The overlapping layer of an icon: multiplied on a light tile, plain on a dark one. */
const M = { mixBlendMode: "var(--app-blend, multiply)" } as unknown as React.CSSProperties;

const gearTeeth = (cx: number, cy: number, r: number, w: number, h: number, fill: string, n = 8) =>
  Array.from({ length: n }, (_, i) => (
    <rect key={i} x={cx - w / 2} y={cy - r - h / 2} width={w} height={h} rx={1.2} fill={fill}
      transform={`rotate(${(360 / n) * i} ${cx} ${cy})`} />
  ));

const GLYPHS: Record<AreaKey, ReactNode> = {
  vouchflow: (
    <>
      <rect x="10" y="6" width="23" height="31" rx="4" fill={C.blue} />
      <rect x="14.5" y="12" width="14" height="3" rx="1.5" fill="#fff" opacity=".9" />
      <rect x="14.5" y="18" width="10" height="3" rx="1.5" fill="#fff" opacity=".9" />
      <circle cx="32" cy="33" r="9.5" fill={C.amber} style={M} />
      <path d="M27.5 33.2l3.2 3.2 6-6.6" stroke={C.navy} strokeWidth="3" fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </>
  ),
  inventory: (
    <>
      <polygon points="24,7 41,15.5 24,24 7,15.5" fill={C.amber} />
      <polygon points="7,15.5 24,24 24,42 7,33.5" fill={C.coral} />
      <polygon points="41,15.5 41,33.5 24,42 24,24" fill={C.navy} />
    </>
  ),
  sales: (
    <>
      <path d="M9 11.5A2.5 2.5 0 0 1 11.5 9H24l15 15-15 15L9 24z" fill={C.mint} strokeLinejoin="round" />
      <circle cx="16.5" cy="16.5" r="3.2" fill="#fff" />
      <circle cx="33" cy="33" r="9" fill={C.coral} style={M} />
    </>
  ),
  dispatch: (
    <>
      <rect x="5" y="11" width="25" height="20" rx="3.5" fill={C.sky} />
      <path d="M27 17h8.5a3 3 0 0 1 2.6 1.5l3.4 6V31H27z" fill={C.blue} style={M} />
      <rect x="31" y="19.5" width="5.5" height="4.5" rx="1.2" fill="#fff" opacity=".9" />
      <circle cx="14" cy="33.5" r="5" fill={C.navy} />
      <circle cx="35" cy="33.5" r="5" fill={C.navy} />
      <circle cx="14" cy="33.5" r="1.8" fill="#fff" />
      <circle cx="35" cy="33.5" r="1.8" fill="#fff" />
    </>
  ),
  procurement: (
    <>
      <rect x="13" y="5" width="9" height="12" rx="2" fill={C.amber} />
      <rect x="23" y="3" width="9" height="14" rx="2" fill={C.mint} />
      <path d="M7 13h34l-4.2 17.2a3 3 0 0 1-2.9 2.3H14.2a3 3 0 0 1-2.9-2.3z" fill={C.coral} style={M} />
      <circle cx="16" cy="39" r="3.6" fill={C.navy} />
      <circle cx="32" cy="39" r="3.6" fill={C.navy} />
    </>
  ),
  finance: (
    <>
      <circle cx="18" cy="28.5" r="12.5" fill={C.amber} />
      <circle cx="30" cy="19.5" r="12.5" fill={C.violet} style={M} />
      <path d="M21.5 25.5l5-5 4 3 6.5-7.5" stroke="#fff" strokeWidth="3" fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </>
  ),
  assets: (
    <>
      <rect x="8" y="15" width="17" height="27" rx="2.5" fill={C.navy} />
      <rect x="22" y="6" width="18" height="36" rx="2.5" fill={C.sky} style={M} />
      {[12, 18.5, 25].map((y) => [27, 33.5].map((x) => <rect key={`${x}-${y}`} x={x} y={y} width="3.5" height="3.5" rx=".8" fill="#fff" opacity=".9" />))}
      <rect x="13" y="33" width="7" height="9" rx="1.5" fill={C.amber} />
    </>
  ),
  production: (
    <>
      {gearTeeth(20, 27, 11.5, 5, 6, C.mint)}
      <circle cx="20" cy="27" r="11.5" fill={C.mint} />
      <circle cx="20" cy="27" r="4.5" fill="#fff" />
      {gearTeeth(33, 15, 7.5, 3.6, 4.5, C.coral, 6)}
      <circle cx="33" cy="15" r="7.5" fill={C.coral} style={M} />
      <circle cx="33" cy="15" r="2.6" fill="#fff" />
    </>
  ),
  fleet: (
    <>
      <path d="M9 39c8-6 4-15 15-17s8-12 15-14" stroke={C.sky} strokeWidth="6" fill="none" strokeLinecap="round" />
      <circle cx="9" cy="39" r="4.2" fill={C.navy} />
      <path d="M30 4.5a9 9 0 0 1 9 9c0 6.8-9 15.5-9 15.5s-9-8.7-9-15.5a9 9 0 0 1 9-9z" fill={C.coral} style={M} />
      <circle cx="30" cy="13.5" r="3.3" fill="#fff" />
    </>
  ),
  hr: (
    <>
      <circle cx="31" cy="14" r="6.5" fill={C.sky} />
      <rect x="21" y="22.5" width="20" height="15" rx="7.5" fill={C.sky} />
      <circle cx="18.5" cy="17.5" r="7.5" fill={C.rose} style={M} />
      <rect x="7" y="27" width="23" height="15" rx="7.5" fill={C.amber} style={M} />
    </>
  ),
  crm: (
    <>
      <path d="M8 10.5A2.5 2.5 0 0 1 10.5 8h27a2.5 2.5 0 0 1 1.9 4.1L28.5 25v12.6a2 2 0 0 1-1.1 1.8l-5 2.5a2 2 0 0 1-2.9-1.8V25L8.6 12.1A2.5 2.5 0 0 1 8 10.5z" fill={C.mint} />
      <circle cx="34" cy="33" r="8.5" fill={C.violet} style={M} />
    </>
  ),
  files: (
    <>
      <path d="M6 12.5A3.5 3.5 0 0 1 9.5 9h8.6a3 3 0 0 1 2.1.9L23.5 13h15a3.5 3.5 0 0 1 3.5 3.5V36a3.5 3.5 0 0 1-3.5 3.5h-29A3.5 3.5 0 0 1 6 36z" fill={C.amber} />
      <rect x="13" y="7" width="20" height="18" rx="2.5" fill="#fff" opacity=".95" />
      <path d="M6 21h36v15a3.5 3.5 0 0 1-3.5 3.5h-29A3.5 3.5 0 0 1 6 36z" fill={C.coral} style={M} />
    </>
  ),
  settings: (
    <>
      {[13, 23, 33].map((y) => <rect key={y} x="7" y={y} width="34" height="4" rx="2" fill={C.navy} opacity=".22" />)}
      <circle cx="16" cy="15" r="5.5" fill={C.blue} />
      <circle cx="32" cy="25" r="5.5" fill={C.mint} />
      <circle cx="21" cy="35" r="5.5" fill={C.coral} />
    </>
  ),
  platform: (
    <>
      <circle cx="24" cy="24" r="16" fill={C.sky} />
      <ellipse cx="19.5" cy="19" rx="7.5" ry="5" fill={C.mint} style={M} />
      <ellipse cx="31" cy="31" rx="6" ry="4.2" fill={C.mint} style={M} />
      <ellipse cx="24" cy="24" rx="21" ry="7" stroke={C.navy} strokeWidth="2.6" fill="none" transform="rotate(-22 24 24)" />
    </>
  ),
};

/**
 * An app's icon, the same wherever the app is named (launcher, sidebar,
 * public pages), so people learn to find an app by its picture.
 */
export function AppIcon({ area, size = 56, badge }: { area: Area; size?: number; badge?: number }) {
  return (
    <span className="app-icon" style={{ "--app-icon": `${size}px` } as React.CSSProperties} aria-hidden="true">
      <svg viewBox="0 0 48 48" width="68%" height="68%" focusable="false">{GLYPHS[area.key]}</svg>
      {badge ? <span className="app-icon-badge tnum">{badge > 99 ? "99+" : badge}</span> : null}
    </span>
  );
}

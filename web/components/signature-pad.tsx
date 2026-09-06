"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useApp } from "@/lib/app-context";
import { Icon } from "@/components/ui";

/**
 * Draw / upload / reuse a saved signature.
 * Pointer events cover mouse, pen and touch, so the same component serves the
 * desktop dialog and the phone.
 */
export function SignaturePad({
  value, onChange, hasSaved, savedSignature,
}: {
  value: string | null;
  onChange: (dataUrl: string | null) => void;
  hasSaved: boolean;
  savedSignature?: string | null;
}) {
  const { t } = useApp();
  const [mode, setMode] = useState<"draw" | "upload" | "saved">(hasSaved ? "saved" : "draw");
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const drawing = useRef(false);
  const dirty = useRef(false);

  // Size the backing store to the element so strokes are not blurred or offset.
  const prepare = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const ratio = window.devicePixelRatio || 1;
    if (canvas.width === Math.round(rect.width * ratio)) return;
    canvas.width = Math.round(rect.width * ratio);
    canvas.height = Math.round(rect.height * ratio);
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.scale(ratio, ratio);
    ctx.lineWidth = 2.2;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.strokeStyle = "#201e1d";
  }, []);

  useEffect(() => {
    if (mode !== "draw") return;
    prepare();
    const onResize = () => prepare();
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, [mode, prepare]);

  useEffect(() => {
    if (mode === "saved" && savedSignature) onChange(savedSignature);
    if (mode === "draw" && !dirty.current) onChange(null);
  }, [mode, savedSignature, onChange]);

  function position(event: React.PointerEvent<HTMLCanvasElement>) {
    const canvas = canvasRef.current!;
    const rect = canvas.getBoundingClientRect();
    return [event.clientX - rect.left, event.clientY - rect.top] as const;
  }

  function commit() {
    const canvas = canvasRef.current;
    if (!canvas || !dirty.current) return;
    // Flatten onto white so the PNG reads on paper as well as on screen.
    const out = document.createElement("canvas");
    out.width = canvas.width;
    out.height = canvas.height;
    const ctx = out.getContext("2d")!;
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, out.width, out.height);
    ctx.drawImage(canvas, 0, 0);
    onChange(out.toDataURL("image/png"));
  }

  function clear() {
    const canvas = canvasRef.current;
    if (canvas) {
      const ctx = canvas.getContext("2d")!;
      ctx.clearRect(0, 0, canvas.width, canvas.height);
    }
    dirty.current = false;
    onChange(null);
  }

  const tabs: Array<{ key: typeof mode; label: string; disabled?: boolean }> = [
    { key: "draw", label: t("drawSignature") },
    { key: "upload", label: t("uploadSignature") },
    { key: "saved", label: t("savedSignature"), disabled: !hasSaved },
  ];

  return (
    <div>
      <div className="seg" style={{ marginBottom: "var(--space-2)" }} role="tablist">
        {tabs.map((tab) => (
          <button
            key={tab.key} type="button" role="tab" aria-selected={mode === tab.key} disabled={tab.disabled}
            onClick={() => { setMode(tab.key); if (tab.key !== "draw") dirty.current = false; }}
            style={{
              border: 0, padding: "7px 12px", fontSize: 13, cursor: tab.disabled ? "not-allowed" : "pointer",
              fontFamily: "var(--font-body)", opacity: tab.disabled ? .45 : 1,
              background: mode === tab.key ? "var(--color-text)" : "transparent",
              color: mode === tab.key ? "var(--color-bg)" : "var(--color-text)",
            }}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {mode === "draw" && (
        <div>
          <canvas
            ref={canvasRef}
            aria-label={t("signWithFinger")}
            style={{
              width: "100%", height: 150, background: "#fff", touchAction: "none",
              border: "1px solid var(--color-neutral-400)", borderRadius: "var(--radius-md)", cursor: "crosshair",
            }}
            onPointerDown={(e) => {
              prepare();
              drawing.current = true;
              e.currentTarget.setPointerCapture(e.pointerId);
              const ctx = canvasRef.current!.getContext("2d")!;
              const [x, y] = position(e);
              ctx.beginPath();
              ctx.moveTo(x, y);
            }}
            onPointerMove={(e) => {
              if (!drawing.current) return;
              const ctx = canvasRef.current!.getContext("2d")!;
              const [x, y] = position(e);
              ctx.lineTo(x, y);
              ctx.stroke();
              dirty.current = true;
            }}
            onPointerUp={() => { drawing.current = false; commit(); }}
            onPointerLeave={() => { if (drawing.current) { drawing.current = false; commit(); } }}
          />
          <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", marginTop: 6 }}>
            <span style={{ fontSize: 12.5, color: "var(--color-neutral-600)", flex: 1 }}>{t("signWithFinger")}</span>
            <button type="button" className="btn btn-ghost btn-sm" onClick={clear}>
              <Icon name="ph-eraser" size={14} /> {t("clearSignature")}
            </button>
          </div>
        </div>
      )}

      {mode === "upload" && (
        <div>
          <input
            className="input" type="file" accept="image/png,image/jpeg,image/webp"
            onChange={(e) => {
              const file = e.target.files?.[0];
              if (!file) return onChange(null);
              const reader = new FileReader();
              reader.onload = () => onChange(String(reader.result));
              reader.readAsDataURL(file);
            }}
          />
          {value && <img src={value} alt="Signature preview" style={{ marginTop: 10, maxHeight: 120, background: "#fff", border: "1px solid var(--color-divider)" }} />}
        </div>
      )}

      {mode === "saved" && (
        hasSaved && savedSignature
          ? <img src={savedSignature} alt="Saved signature" style={{ maxHeight: 130, background: "#fff", border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)", padding: 6 }} />
          : <div style={{ fontSize: 14, color: "var(--color-neutral-700)" }}>No saved signature yet — draw one and tick &ldquo;save for next time&rdquo;.</div>
      )}
    </div>
  );
}

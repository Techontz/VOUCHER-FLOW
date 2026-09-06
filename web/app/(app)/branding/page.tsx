"use client";

import { useEffect, useState } from "react";
import { request } from "@/lib/api";
import { useApp } from "@/lib/app-context";
import { Field, Icon, LoadingBlock, PageHeader, SectionTitle, Spinner } from "@/components/ui";

export default function BrandingPage() {
  const { t, company, refresh, toast, reportError } = useApp();
  const [primary, setPrimary] = useState("#0088b0");
  const [footer, setFooter] = useState("");
  const [logo, setLogo] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!company) return;
    setPrimary(company.primary_color);
    setFooter(company.voucher_footer_text ?? "");
    setPreview(company.logo_url);
  }, [company]);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      const form = new FormData();
      form.append("primary_color", primary);
      form.append("voucher_footer_text", footer);
      if (logo) form.append("logo", logo);
      await request("/company/branding", { method: "POST", form });
      await refresh();
      setLogo(null);
      toast("Branding saved", "Your logo and colour now appear on every voucher.", "ok");
    } catch (err) { reportError(err, "Could not save branding"); }
    finally { setBusy(false); }
  }

  async function removeLogo() {
    setBusy(true);
    try {
      const form = new FormData();
      form.append("remove_logo", "1");
      await request("/company/branding", { method: "POST", form });
      await refresh();
      setPreview(null);
      toast("Logo removed", undefined, "warn");
    } catch (err) { reportError(err, "Could not remove the logo"); }
    finally { setBusy(false); }
  }

  if (!company) return <LoadingBlock rows={4} />;

  return (
    <div style={{ maxWidth: 1080 }}>
      <PageHeader kicker={t("settings")} title={t("branding")}
        sub="Your logo, colour and footer line are applied to the interface and printed on every voucher." />

      <div className="vf-split">
        <form onSubmit={save} style={{ display: "grid", gap: "var(--space-4)" }}>
          <Field label={t("logo")} htmlFor="b-logo" hint="PNG or JPG, up to 2 MB">
            <input id="b-logo" className="input" type="file" accept="image/*"
              onChange={(e) => {
                const file = e.target.files?.[0] ?? null;
                setLogo(file);
                if (file) setPreview(URL.createObjectURL(file));
              }} />
          </Field>

          {preview && (
            <div style={{ display: "flex", alignItems: "center", gap: "var(--space-3)" }}>
              <img src={preview} alt="Logo preview" style={{ maxHeight: 60, background: "#fff", border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)", padding: 6 }} />
              <button type="button" className="btn btn-secondary btn-sm btn-danger" onClick={removeLogo} disabled={busy}>
                {t("remove")}
              </button>
            </div>
          )}

          <Field label={t("primaryColour")} htmlFor="b-colour">
            <div style={{ display: "flex", gap: "var(--space-2)", alignItems: "center", flexWrap: "wrap" }}>
              <input id="b-colour" type="color" value={primary} onChange={(e) => setPrimary(e.target.value)}
                style={{ width: 52, height: 36, border: "1px solid var(--color-divider)", borderRadius: "var(--radius-md)", background: "transparent", cursor: "pointer" }} />
              <input className="input" value={primary} onChange={(e) => setPrimary(e.target.value)} style={{ maxWidth: 140 }} />
              {["#0088b0", "#d6006c", "#1f6f4a", "#8a4b12"].map((c) => (
                <button key={c} type="button" onClick={() => setPrimary(c)} aria-label={`Use ${c}`}
                  style={{ width: 30, height: 30, background: c, border: primary === c ? "2px solid var(--color-text)" : "1px solid var(--color-divider)", borderRadius: "var(--radius-md)", cursor: "pointer" }} />
              ))}
            </div>
          </Field>

          <Field label={t("voucherFooterText")} htmlFor="b-footer" hint="Printed at the foot of every voucher PDF">
            <textarea id="b-footer" className="input" value={footer} onChange={(e) => setFooter(e.target.value)} style={{ minHeight: 78 }} />
          </Field>

          <div><button className="btn btn-primary" disabled={busy}>{busy ? <Spinner /> : t("saveChanges")}</button></div>
        </form>

        <div className="vf-sticky">
          <SectionTitle>{t("liveVoucherPreview")}</SectionTitle>
          <div style={{ background: "#fff", color: "#201e1d", border: "1px solid var(--color-neutral-300)", boxShadow: "var(--shadow-md)", padding: 26, fontSize: 13 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", borderBottom: `3px solid ${primary}`, paddingBottom: 12, gap: 12 }}>
              <div style={{ minWidth: 0 }}>
                {preview && <img src={preview} alt="" style={{ maxHeight: 32, marginBottom: 6 }} />}
                <div style={{ fontFamily: "var(--font-heading)", fontWeight: 700, fontSize: 17 }}>{company.name}</div>
                <div style={{ color: "#605d5d", fontSize: 11.5 }}>{[company.address, company.phone].filter(Boolean).join(" · ")}</div>
              </div>
              <div style={{ textAlign: "right", flex: "none" }}>
                <div style={{ fontSize: 10.5, letterSpacing: ".12em", textTransform: "uppercase", color: "#605d5d" }}>Payment Voucher</div>
                <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 15, fontVariantNumeric: "tabular-nums" }}>PV-2026-000042</div>
              </div>
            </div>
            <div style={{ padding: "14px 0", borderBottom: "1px solid #d7d3d3" }}>
              <div style={{ fontSize: 10.5, textTransform: "uppercase", letterSpacing: ".08em", color: "#605d5d" }}>Payment purpose</div>
              <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 15, margin: "2px 0" }}>Office consumables — September</div>
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", padding: "12px 0", borderBottom: `3px solid ${primary}` }}>
              <div style={{ fontStyle: "italic", color: "#444141" }}>Three hundred Fifty thousand shillings only</div>
              <div style={{ fontFamily: "var(--font-heading)", fontWeight: 600, fontSize: 20, fontVariantNumeric: "tabular-nums" }}>TZS 350,000</div>
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 18, paddingTop: 16 }}>
              <div><div style={{ borderBottom: "1px solid #9b9797", height: 30 }} /><div style={{ fontSize: 10.5, color: "#605d5d", marginTop: 4 }}>Signed by (HOD)</div></div>
              <div><div style={{ borderBottom: "1px solid #9b9797", height: 30 }} /><div style={{ fontSize: 10.5, color: "#605d5d", marginTop: 4 }}>Approved by (Manager)</div></div>
            </div>
            <div style={{ marginTop: 18, paddingTop: 10, borderTop: "1px solid #eae7e7", fontSize: 10.5, color: "#605d5d" }}>
              {footer || "This voucher is computer generated."}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

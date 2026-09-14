"use client";

import { useApp } from "@/lib/app-context";
import { Icon } from "@/components/ui";
import { MOCK, pick, type VoucherTab } from "./copy";

/**
 * Product pictures for the public site, drawn with the product's own parts —
 * the same status badges, progress marks, kind chips and tones the app uses —
 * so what a visitor sees here is what they get after signing in.
 *
 * They are illustrations: every value is fixed, nothing is fetched, and each
 * one is hidden from assistive technology with a one-line description instead.
 */

type Locale = "en" | "sw";

function Figure({ label, className, children }: { label: string; className?: string; children: React.ReactNode }) {
  return (
    <figure className={`lp-figure ${className ?? ""}`}>
      <figcaption className="sr-only">{label}</figcaption>
      <div aria-hidden="true" className="lp-figure-body">{children}</div>
    </figure>
  );
}

function Step({ state, title, who, when }: { state: "done" | "current" | "next"; title: string; who?: string; when?: string }) {
  return (
    <li className="lp-track-step" data-state={state}>
      <span className="lp-track-mark">
        {state === "done" && <Icon name="ph-check" size={12} />}
      </span>
      <span className="lp-track-text">
        <strong>{title}</strong>
        {who && <span>{who}</span>}
      </span>
      {when && <span className="lp-track-when">{when}</span>}
    </li>
  );
}

/** A tiny drawn signature, so a "signed" step looks signed. */
function Scribble({ className }: { className?: string }) {
  return (
    <svg className={`lp-scribble ${className ?? ""}`} viewBox="0 0 120 36" fill="none">
      <path d="M4 26c8-14 14-20 18-18s-4 20 2 20 10-22 16-22-2 18 4 18 8-12 14-12 2 10 8 10 10-8 16-9 10 4 16 1 10-6 16-7"
        stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/* ───────────────────────────────────────────────────────────── hero ── */

export function HeroVisual() {
  const { locale } = useApp();
  const l = (e: readonly [string, string]) => pick(e, locale as Locale);

  return (
    <Figure label={l(MOCK.illustration)} className="lp-hero-visual">
      <div className="lp-card lp-voucher">
        <div className="lp-voucher-top">
          <span className="lp-voucher-type">{l(MOCK.paymentVoucher)}</span>
          <span className="vf-kind"><Icon name="ph-bank" /> Bank</span>
        </div>
        <div className="lp-voucher-number tnum">PV-2026-000049</div>
        <div className="lp-voucher-amount tnum"><span>TZS</span> 345,678</div>
        <span className="badge tone-warn">{l(MOCK.awaitingCeo)}</span>

        <dl className="lp-voucher-meta">
          <div><dt>{l(MOCK.requestedBy)}</dt><dd>Frank Kessy · Procurement</dd></div>
          <div><dt>{l(MOCK.payee)}</dt><dd>Afiya Packaging Ltd</dd></div>
          <div><dt>{l(MOCK.purpose)}</dt><dd>PET preforms for the 500 ml line</dd></div>
        </dl>

        <div className="lp-files">
          <span><Icon name="ph-file-pdf" size={15} /> INV-88213.pdf</span>
          <span><Icon name="ph-image" size={15} /> delivery-note.jpg</span>
        </div>

        <ol className="lp-track">
          <Step state="done" title={l(MOCK.prepared)} who="Frank Kessy" when="09:12" />
          <Step state="done" title={l(MOCK.hodSigned)} who="Joseph Mrisho" when="10:40" />
          <Step state="current" title={l(MOCK.ceoApproval)} who={l(MOCK.waiting)} />
          <Step state="next" title={l(MOCK.financePayment)} who={l(MOCK.next)} />
        </ol>
      </div>

      <div className="lp-card lp-notify">
        <span className="lp-notify-icon"><Icon name="ph-bell-ringing" size={18} /></span>
        <div className="lp-notify-text">
          <strong>{l(MOCK.approvalRequired)}</strong>
          <span><span className="tnum">PV-2026-000049</span> {l(MOCK.waitingForYou)}</span>
        </div>
        <div className="lp-notify-actions">
          <span className="lp-btn lp-btn-quiet">{l(MOCK.review)}</span>
          <span className="lp-btn lp-btn-solid">{l(MOCK.approve)}</span>
        </div>
      </div>

      <div className="lp-card lp-signed">
        <span className="lp-signed-icon"><Icon name="ph-signature" size={16} /></span>
        <span><strong>{l(MOCK.signed)}</strong> · Joseph Mrisho, HOD</span>
      </div>
    </Figure>
  );
}

/* ─────────────────────────────────────────────────── voucher tabs ── */

export function VoucherVisual({ tab }: { tab: VoucherTab }) {
  const { locale } = useApp();
  const sw = locale === "sw";

  if (tab === "attachments") {
    return (
      <Figure label="Attachments on a voucher" className="lp-panel-visual">
        <div className="lp-card lp-pad">
          <div className="lp-head-row"><strong>{sw ? "Viambatisho" : "Attachments"}</strong><span className="vf-count">3</span></div>
          <ul className="lp-filelist">
            {[
              ["ph-file-pdf", "INV-88213.pdf", "184 KB", sw ? "Ankara" : "Invoice"],
              ["ph-file-pdf", "QT-2026-114.pdf", "96 KB", sw ? "Nukuu" : "Quotation"],
              ["ph-image", "delivery-note.jpg", "1.2 MB", sw ? "Hati ya kupokea" : "Delivery note"],
            ].map(([icon, name, size, kind]) => (
              <li key={name}>
                <span className="lp-file-icon"><Icon name={icon} size={20} /></span>
                <span className="lp-file-text"><strong>{name}</strong><span>{kind} · {size}</span></span>
                <Icon name="ph-download-simple" size={17} />
              </li>
            ))}
          </ul>
          <div className="lp-dropzone"><Icon name="ph-upload-simple" size={18} /> {sw ? "Weka faili hapa, au chagua" : "Drop files here, or browse"}</div>
        </div>
      </Figure>
    );
  }

  if (tab === "signatures") {
    return (
      <Figure label="Signing a voucher" className="lp-panel-visual">
        <div className="lp-card lp-pad">
          <div className="lp-head-row"><strong>{sw ? "Thibitisha saini" : "Confirm signature"}</strong><span className="badge tone-info">PV-2026-000049</span></div>
          <div className="lp-sigpad"><Scribble /></div>
          <div className="lp-summary">
            <div><span>{sw ? "Anayesaini" : "Signing as"}</span><strong>Joseph Mrisho · HOD</strong></div>
            <div><span>{sw ? "Kiasi" : "Amount"}</span><strong className="tnum">TZS 345,678</strong></div>
            <div><span>{sw ? "Tarehe" : "Date"}</span><strong className="tnum">14 Sep 2026 · 10:40</strong></div>
          </div>
          <div className="lp-actions"><span className="lp-btn lp-btn-quiet">{sw ? "Ghairi" : "Cancel"}</span><span className="lp-btn lp-btn-solid"><Icon name="ph-signature" size={15} /> {sw ? "Saini vocha" : "Sign voucher"}</span></div>
        </div>
      </Figure>
    );
  }

  const cash = tab === "cash";
  return (
    <Figure label="A printed voucher" className="lp-panel-visual">
      <div className="lp-sheet">
        <div className="lp-sheet-head">
          <span className="lp-sheet-logo">AP</span>
          <div><strong>Afiya Beverages Ltd</strong><span>P.O. Box 7020, Dar es Salaam</span></div>
          <div className="lp-sheet-no"><span>{cash ? (sw ? "VOCHA YA TASLIMU" : "CASH VOUCHER") : (sw ? "VOCHA YA MALIPO" : "PAYMENT VOUCHER")}</span><strong className="tnum">{cash ? "CV-2026-000112" : "PV-2026-000049"}</strong></div>
        </div>
        <dl className="lp-sheet-grid">
          <div><dt>{sw ? "Mlipwaji" : "Pay to"}</dt><dd>{cash ? "Amina Said" : "Afiya Packaging Ltd"}</dd></div>
          <div><dt>{sw ? "Kiasi" : "Amount"}</dt><dd className="tnum">TZS {cash ? "85,000" : "345,678"}</dd></div>
          <div className="lp-wide"><dt>{sw ? "Kwa maneno" : "In words"}</dt><dd>{cash ? "Eighty-five thousand shillings only" : "Three hundred forty-five thousand six hundred seventy-eight shillings only"}</dd></div>
          {tab === "bank" || tab === "payment" ? (
            <>
              <div><dt>{sw ? "Benki" : "Bank"}</dt><dd>CRDB Bank · Tower</dd></div>
              <div><dt>{sw ? "Akaunti" : "Account"}</dt><dd className="tnum">0150 2211 8890 1</dd></div>
            </>
          ) : (
            <>
              <div><dt>{sw ? "Kutoka akiba" : "Paid from"}</dt><dd>Kibada petty cash</dd></div>
              <div><dt>{sw ? "Imepokelewa na" : "Received by"}</dt><dd>Amina Said</dd></div>
            </>
          )}
        </dl>
        <div className="lp-sheet-signs">
          {[[sw ? "Imeandaliwa" : "Prepared", "F. Kessy"], [sw ? "Imesainiwa" : "Signed", "J. Mrisho"], [sw ? "Imeidhinishwa" : "Approved", "E. Massawe"]].map(([role, name]) => (
            <div key={role}><Scribble /><span>{role}</span><strong>{name}</strong></div>
          ))}
        </div>
      </div>
    </Figure>
  );
}

/* ────────────────────────────────────────────────── workflow builder ── */

export function BuilderVisual() {
  const { locale } = useApp();
  const sw = locale === "sw";
  const steps = [
    { n: 1, name: sw ? "Ombi" : "Request", role: sw ? "Mfanyakazi" : "Employee", caps: [sw ? "Andaa" : "Create"] },
    { n: 2, name: sw ? "Mapitio ya idara" : "Department review", role: "HOD", caps: [sw ? "Saini" : "Sign", sw ? "Rudisha" : "Send back"] },
    { n: 3, name: sw ? "Idhini" : "Approval", role: "CEO", caps: [sw ? "Idhinisha" : "Approve", sw ? "Kataa" : "Reject"] },
    { n: 4, name: sw ? "Idhini ya bodi" : "Board approval", role: sw ? "Mkurugenzi" : "Director", caps: [sw ? "Idhinisha" : "Approve"], rule: sw ? "Juu ya TZS 5,000,000" : "Above TZS 5,000,000" },
    { n: 5, name: sw ? "Malipo" : "Payment", role: sw ? "Mhazini" : "Cashier", caps: [sw ? "Lipa" : "Pay", sw ? "Chapisha" : "Print"] },
  ];
  return (
    <Figure label="The workflow builder" className="lp-panel-visual">
      <div className="lp-card lp-pad">
        <div className="lp-head-row">
          <strong>{sw ? "Njia ya kawaida" : "Default route"}</strong>
          <span className="badge tone-ok">{sw ? "Inatumika" : "Active"}</span>
        </div>
        <ol className="lp-builder">
          {steps.map((s) => (
            <li key={s.n} data-rule={s.rule ? "true" : undefined}>
              <span className="lp-builder-num tnum">{s.n}</span>
              <div className="lp-builder-body">
                <div className="lp-builder-title"><strong>{s.name}</strong><span>{s.role}</span></div>
                <div className="lp-builder-caps">
                  {s.caps.map((c) => <span key={c} className="lp-cap">{c}</span>)}
                  {s.rule && <span className="lp-cap lp-cap-rule"><Icon name="ph-scales" size={12} /> {s.rule}</span>}
                </div>
              </div>
            </li>
          ))}
        </ol>
      </div>
    </Figure>
  );
}

/* ───────────────────────────────────────────────────────────── audit ── */

export function AuditVisual() {
  const { locale } = useApp();
  const sw = locale === "sw";
  const rows = [
    { icon: "ph-note-pencil", tone: "neutral", what: sw ? "Imeandaliwa na kuwasilishwa" : "Prepared and submitted", who: "Frank Kessy", role: sw ? "Mfanyakazi" : "Employee", when: "14 Sep · 09:12", extra: sw ? "Viambatisho 2" : "2 attachments" },
    { icon: "ph-signature", tone: "info", what: sw ? "Imesainiwa" : "Signed", who: "Joseph Mrisho", role: "HOD", when: "14 Sep · 10:40", extra: sw ? "Saini imethibitishwa" : "Signature confirmed" },
    { icon: "ph-seal-check", tone: "ok", what: sw ? "Imeidhinishwa" : "Approved", who: "Emmanuel Massawe", role: "CEO", when: "14 Sep · 14:05" },
    { icon: "ph-hand-coins", tone: "ok", what: sw ? "Imelipwa" : "Paid", who: "Mwajuma Hamisi", role: sw ? "Mhazini" : "Cashier", when: "15 Sep · 08:30", extra: "Ref TRX-55120" },
  ];
  return (
    <Figure label="A voucher's audit trail" className="lp-panel-visual">
      <div className="lp-card lp-pad">
        <div className="lp-head-row">
          <strong className="tnum">PV-2026-000049</strong>
          <span className="badge tone-ok">{sw ? "Imelipwa" : "Paid"}</span>
        </div>
        <ol className="lp-audit">
          {rows.map((r) => (
            <li key={r.what}>
              <span className={`lp-audit-icon tone-${r.tone}`}><Icon name={r.icon} size={16} /></span>
              <div className="lp-audit-text">
                <strong>{r.what}</strong>
                <span>{r.who} · {r.role}{r.extra ? ` · ${r.extra}` : ""}</span>
              </div>
              <span className="lp-audit-when tnum">{r.when}</span>
            </li>
          ))}
        </ol>
      </div>
    </Figure>
  );
}

/* ───────────────────────────────────────────────────────── companies ── */

export function CompaniesVisual() {
  const { locale } = useApp();
  const sw = locale === "sw";
  const companies = [
    { ini: "AB", name: "Afiya Beverages Ltd", color: "#2563eb", people: 48, wf: sw ? "Hatua 4" : "4 steps" },
    { ini: "ZL", name: "Zamani Logistics", color: "#0f766e", people: 22, wf: sw ? "Hatua 3" : "3 steps" },
    { ini: "TH", name: "Tembo Holdings", color: "#b45309", people: 131, wf: sw ? "Hatua 5" : "5 steps" },
  ];
  return (
    <Figure label="Several companies, each kept separate" className="lp-panel-visual">
      <div className="lp-card lp-pad">
        <div className="lp-head-row"><strong>{sw ? "Kampuni" : "Companies"}</strong><span className="lp-lock"><Icon name="ph-lock-key" size={14} /> {sw ? "Zimetenganishwa" : "Isolated"}</span></div>
        <ul className="lp-companies">
          {companies.map((c) => (
            <li key={c.name}>
              <span className="lp-company-logo" style={{ background: c.color }}>{c.ini}</span>
              <span className="lp-company-text"><strong>{c.name}</strong><span>{c.people} {sw ? "watumiaji" : "people"} · {c.wf}</span></span>
              <span className="lp-swatch" style={{ background: c.color }} />
            </li>
          ))}
        </ul>
      </div>
    </Figure>
  );
}

/* ─────────────────────────────────────────────────────────── reports ── */

export function ReportsVisual() {
  const { locale } = useApp();
  const sw = locale === "sw";
  const bars = [
    [sw ? "Manunuzi" : "Procurement", 82], [sw ? "Usafirishaji" : "Transport", 58],
    [sw ? "Uzalishaji" : "Production", 46], [sw ? "Utawala" : "Admin", 24],
  ] as const;
  return (
    <Figure label="A voucher report" className="lp-panel-visual">
      <div className="lp-card lp-pad">
        <div className="lp-head-row">
          <strong>{sw ? "Ripoti ya Septemba" : "September report"}</strong>
          <span className="lp-exports"><span className="lp-btn lp-btn-quiet"><Icon name="ph-file-xls" size={14} /> Excel</span><span className="lp-btn lp-btn-quiet"><Icon name="ph-printer" size={14} /> {sw ? "Chapisha" : "Print"}</span></span>
        </div>
        <div className="lp-report-kpis">
          <div><span>{sw ? "Zilizoidhinishwa" : "Approved"}</span><strong className="tnum">TZS 48.2M</strong></div>
          <div><span>{sw ? "Zilizolipwa" : "Paid"}</span><strong className="tnum">TZS 41.7M</strong></div>
          <div><span>{sw ? "Zinasubiri" : "Waiting"}</span><strong className="tnum">12</strong></div>
        </div>
        <div className="lp-bars">
          {bars.map(([name, pct]) => (
            <div key={name} className="lp-bar-row">
              <span>{name}</span>
              <span className="lp-bar"><span style={{ width: `${pct}%` }} /></span>
            </div>
          ))}
        </div>
      </div>
    </Figure>
  );
}

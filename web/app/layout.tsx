import type { Metadata, Viewport } from "next";
import "./globals.css";
import { AppProvider } from "@/lib/app-context";
import { Toasts } from "@/components/ui";

export const metadata: Metadata = {
  title: "VouchFlow — voucher approvals, signed and on the record",
  description:
    "Create, review, sign, approve and track business vouchers. Configurable approval workflows, digital signatures, A4 PDF vouchers and a full audit trail.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f6f7f9" },
    { media: "(prefers-color-scheme: dark)", color: "#0e1116" },
  ],
};

/**
 * Applied before the first paint, so a returning visitor who chose dark never
 * sees a light frame flash first (and vice versa). Dark is the default when
 * nothing has been stored — the operating system's preference is deliberately
 * not consulted. The company's colour theme is restored the same way.
 */
const THEME_BOOTSTRAP = `(function(){var d=document.documentElement;try{var t=localStorage.getItem("vouchflow.theme");d.dataset.theme=(t==="light"||t==="dark")?t:"dark";var a=localStorage.getItem("vouchflow.accent");if(/^(blue|emerald|violet|rose)$/.test(a||""))d.dataset.accent=a;var sb=localStorage.getItem("vouchflow.sidebar");if(sb==="1"||(sb===null&&innerWidth<1280))d.dataset.sidebar="collapsed";}catch(e){d.dataset.theme="dark";}})();`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" data-theme="dark" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOTSTRAP }} />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700;800&display=swap"
        />
        <link rel="stylesheet" href="https://unpkg.com/@phosphor-icons/web@2.1.1/src/regular/style.css" />
        <link rel="stylesheet" href="https://unpkg.com/@phosphor-icons/web@2.1.1/src/fill/style.css" />
      </head>
      <body>
        <AppProvider>
          {children}
          <Toasts />
        </AppProvider>
      </body>
    </html>
  );
}

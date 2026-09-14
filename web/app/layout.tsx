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
 * sees a light frame flash first (and vice versa). Light is the default when
 * nothing has been stored — the operating system's preference is deliberately
 * not consulted.
 */
const THEME_BOOTSTRAP = `(function(){try{var t=localStorage.getItem("vouchflow.theme");document.documentElement.dataset.theme=(t==="light"||t==="dark")?t:"light";}catch(e){document.documentElement.dataset.theme="light";}})();`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" data-theme="light" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOTSTRAP }} />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Poppins:ital,wght@0,300;0,400;0,500;0,600;0,700;1,400;1,500&display=swap"
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
